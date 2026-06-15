import processing.serial.*; // シリアル通信ライブラリをインポート

// ==========================================
// 1. システム制御用の変数定義
// ==========================================
Serial myPort;
boolean isSerialConnected = false; // 実機接続時はsetup内でtrueに切り替わる

int bpm = 120; // 初期BPM（30〜180）

// ドラムは演奏開始からずっと鳴り続けるため演奏順番設定から除外
String[] instNames = {"ピアノ", "フルート", "木琴"}; // ← ドラム削除（3楽器）

// 各楽器の演奏順番（0:未設定，1〜3:演奏順手）
int[] playOrder = {0, 0, 0}; // ← 3要素に変更

// オクターブは楽器共通の1変数（国際式：-1〜9）
int octave = 4;

// 演奏順番の入力管理用変数
int[] orderSelection = {-1, -1, -1}; // ← 3要素に変更
int orderCount = 0;

// 演奏中フラグ（trueの間はBPM以外の変更をロックする）
boolean isPlaying = false;

// ==========================================
// BPM定期送信 ＆ ロック解除ロジック用変数
// ==========================================
// 最初の1回目送信済みフラグ
boolean firstPacketSent = false;

// BPMを送信するたびにカウントアップするカウンタ（スロット進捗の代わり）
int bpmSendCount = 0;

// 楽譜の要素数（Slaveに保存されている楽譜の総スロット数）
final int SCORE_ELEMENT_COUNT = 98;

// 最後の音のduration（秒単位）＋ 余裕1秒でロック解除
// 現在は仮に1秒（1000ms）を設定．変更する場合はここを更新すること
final float LAST_NOTE_DURATION_SEC = 1.0;

// BPM送信間隔を計算するタイマー関連
long lastBpmSendTime = 0; // millis()で管理

// 楽譜終了+1秒後にロック解除するためのタイムスタンプ（-1 = 未設定）
long unlockScheduledTime = -1;

// ==========================================
// 2. UIボタン配置用座標
// ==========================================
int sendX = 610, sendY = 20, sendW = 150, sendH = 32;
int resetX = 610, resetY = 250, resetW = 120, resetH = 40;

// オクターブボタンの配置
int octBtnUpX, octBtnUpY;
int octBtnDownX, octBtnDownY;
int octBtnW = 50, octBtnH = 32;

void setup() {
  size(800, 600);
  String chosenFont = "SansSerif";
  String[] fontList = PFont.list();
  for (String f : fontList) {
    if (f.equals("Meiryo") || f.equals("MS Gothic") ||
        f.equals("Hiragino Kaku Gothic Pro") || f.equals("Yu Gothic")) {
      chosenFont = f;
      break;
    }
  }
  PFont font = createFont(chosenFont, 16, true);
  textFont(font);

  // オクターブボタン座標
  octBtnUpX   = 440;
  octBtnUpY   = 410;
  octBtnDownX = 510;
  octBtnDownY = 410;

  // 【シリアル通信の初期設定】
  // 実機を接続する場合はコメントアウトを解除ポート番号を合わせる
  /*
  try {
    String portName = Serial.list()[0]; // 使用するポートを選択
    myPort = new Serial(this, portName, 115200);
    myPort.bufferUntil('\n'); // 改行コードが来るまでデータを溜める
    isSerialConnected = true;
  } catch (Exception e) {
    println("シリアルポートが見つかりません．シミュレーションモードで起動します．");
  }
  */

  resetOrder();
}

void draw() {
  background(245);

  // ==========================================
  // 演奏中のBPM定期送信 ＆ ロック解除チェック
  // ==========================================
  if (isPlaying) {
    // BPMから送信間隔（ms）を計算
    // 1拍 = 60000 / BPM [ms]
    long intervalMs = (long)(60000.0 / bpm);
    long now = millis();

    // 送信間隔が経過したらBPMを送信
    if (now - lastBpmSendTime >= intervalMs) {
      sendBpmOnly(); // 2回目以降：BPMのみ3バイト送信
      lastBpmSendTime = now;
      bpmSendCount++;
      println("BPM送信 #" + bpmSendCount + "  (要素数: " + SCORE_ELEMENT_COUNT + ")");

      // 楽譜の要素数を満たしたら「最後の音の終了+1秒後」にロック解除をスケジュール
      if (bpmSendCount >= SCORE_ELEMENT_COUNT && unlockScheduledTime < 0) {
        // LAST_NOTE_DURATION_SEC + 1秒（余裕）後にロック解除
        unlockScheduledTime = now + (long)((LAST_NOTE_DURATION_SEC + 1.0) * 1000);
        println("楽譜終了を検出．ロック解除予定時刻をセットしました（" 
                + nf((LAST_NOTE_DURATION_SEC + 1.0), 1, 1) + "秒後）");
      }
    }

    // ロック解除予定時刻に達したらisPlayingをfalseに
    if (unlockScheduledTime > 0 && now >= unlockScheduledTime) {
      isPlaying = false;
      firstPacketSent = false;
      bpmSendCount = 0;
      unlockScheduledTime = -1;
      lastBpmSendTime = 0;
      println("【ロック解除】楽譜終了＋1秒が経過しました．UIを編集可能状態に戻します．");
    }
  }

  // ----------------------------------------
  // A. タイトル ＆ 送信ボタン
  // ----------------------------------------
  fill(40);
  textSize(22);
  text("ハッカソン1 グループ7 演奏制御システム", 40, 46);

  // 送信ボタン（演奏中も送信パケットの再送や停止指示のためにクリックは可能）
  boolean isSendHovered = isHover(sendX, sendY, sendW, sendH);
  fill(isSendHovered ? color(0, 153, 76) : color(0, 204, 102));
  stroke(isSendHovered ? color(0, 102, 51) : color(0, 153, 76));
  strokeWeight(isSendHovered ? 2 : 1);
  rect(sendX, sendY, sendW, sendH, 6);
  noStroke();
  fill(255);
  textSize(14);
  text("設定確定・送信", sendX + 26, sendY + 21);

  // ----------------------------------------
  // B. BPM設定エリア（演奏中も変更可能）
  // ----------------------------------------
  stroke(200); fill(255);
  rect(40, 75, 720, 90, 8);
  noStroke();

  fill(40); textSize(20);
  text("現在の設定BPM: " + bpm, 60, 115);
  fill(120); textSize(13);
  text("【操作方法】[↑] キーで +10 / [↓] キーで -10（範囲：30〜180）※演奏中も可変", 60, 145);

  // ----------------------------------------
  // C. 演奏順番設定エリア（演奏中はロック）
  // ----------------------------------------
  stroke(200); 
  fill(isPlaying ? color(240) : color(255)); // ★演奏中は背景をグレーにしてロック
  rect(40, 185, 720, 190, 8);
  noStroke();

  fill(isPlaying ? color(140) : color(40)); textSize(16);
  text("【演奏順番の設定】" + (isPlaying ? "（演奏中：変更不可）" : ""), 60, 220);
  fill(80); textSize(14);
  // ドラムは演奏順番設定から除外されているため表示しない
  text("楽器番号 ―――  1: ピアノ  |  2: フルート  |  3: 木琴", 60, 250);
  
  if (isPlaying) {
    fill(200, 100, 100);
    text("★ 現在Masterが演奏中．演奏が終了するまで順番変更はできません．", 60, 275);
  } else {
    fill(0, 102, 204);
    text("★ キーボードの [1] ～ [3] キーを演奏したい順番に押してください．", 60, 275);
  }

  fill(50); textSize(14);
  text("現在の演奏ルート：", 60, 330);
  for (int i = 0; i < 3; i++) { // ← ループを3に変更
    int idx = orderSelection[i];
    String name = (idx == -1) ? "未選択" : instNames[idx];
    fill(idx == -1 ? color(160) : (isPlaying ? color(100, 140, 180) : color(0, 102, 204)));
    text("[" + (i + 1) + "番手: " + name + "]", 185 + i * 155, 330); // 間隔を155に調整（3要素）
    if (i < 2) { fill(180); text("→", 300 + i * 155, 330); }
  }

  // 順番リセットボタン（演奏中はグレー）
  if (isPlaying) {
    fill(230); stroke(200);
    rect(resetX, resetY, resetW, resetH, 6); noStroke();
    fill(160); textSize(14);
    text("ロック中", resetX + 32, resetY + 25);
  } else {
    boolean isResetHovered = isHover(resetX, resetY, resetW, resetH);
    fill(isResetHovered ? color(255, 210, 210) : color(255, 235, 235));
    stroke(isResetHovered ? color(204, 0, 0) : color(255, 150, 150));
    rect(resetX, resetY, resetW, resetH, 6); noStroke();
    fill(204, 0, 0); textSize(14);
    text("順番リセット", resetX + 18, resetY + 25);
  }

  // ----------------------------------------
  // D. 共通オクターブ設定エリア（演奏中はロック）
  // ----------------------------------------
  stroke(180); 
  fill(isPlaying ? color(240) : color(255)); // 演奏中は背景をグレー
  rect(40, 390, 720, 80, 8);
  noStroke();

  fill(isPlaying ? color(140) : color(40)); textSize(16);
  text("【共通オクターブ設定】" + (isPlaying ? "（演奏中：変更不可）" : ""), 60, 418);

  fill(50); textSize(14);
  // 2桁表示：国際式 -1→00, 0→01, 1→02, ..., 9→10
  String octDisplay = octave < 0 ? "-1（最低域）" : String.valueOf(octave);
  String octSendStr = nf(octave + 1, 2); // 送信用2桁値
  text("現在のオクターブ: " + octDisplay + "  （送信値: " + octSendStr + "）  （国際式 -1〜9）", 60, 448);

  // ▲ ボタン（演奏中は非活性）
  if (isPlaying) {
    fill(235); stroke(220); rect(octBtnUpX, octBtnUpY, octBtnW, octBtnH, 4); noStroke();
    fill(170); textSize(14); text("▲ +1", octBtnUpX + 7, octBtnUpY + 22);
  } else {
    boolean isUpHover = isHover(octBtnUpX, octBtnUpY, octBtnW, octBtnH);
    fill(isUpHover ? color(215, 235, 255) : color(245));
    stroke(isUpHover ? color(0, 102, 204) : color(210));
    rect(octBtnUpX, octBtnUpY, octBtnW, octBtnH, 4); noStroke();
    fill(40); textSize(14); text("▲ +1", octBtnUpX + 7, octBtnUpY + 22);
  }

  // ▼ ボタン（演奏中は非活性）
  if (isPlaying) {
    fill(235); stroke(220); rect(octBtnDownX, octBtnDownY, octBtnW, octBtnH, 4); noStroke();
    fill(170); textSize(14); text("▼ -1", octBtnDownX + 7, octBtnDownY + 22);
  } else {
    boolean isDownHover = isHover(octBtnDownX, octBtnDownY, octBtnW, octBtnH);
    fill(isDownHover ? color(215, 235, 255) : color(245));
    stroke(isDownHover ? color(0, 102, 204) : color(210));
    rect(octBtnDownX, octBtnDownY, octBtnW, octBtnH, 4); noStroke();
    fill(40); textSize(14); text("▼ -1", octBtnDownX + 7, octBtnDownY + 22);
  }

  // ----------------------------------------
  // E. 各楽器（Slave）ステータスボックス（ドラム除く3楽器）
  // ----------------------------------------
  for (int i = 0; i < 3; i++) { // ← 3楽器に変更
    int boxX = 40 + i * 245; // 間隔を245に調整（3要素）
    int boxY = 490;
    int boxW = 215;
    int boxH = 90;

    stroke(200); fill(255);
    rect(boxX, boxY, boxW, boxH, 8);
    noStroke();

    fill(40); textSize(15);
    text(instNames[i] + " (" + (i + 1) + ")", boxX + 15, boxY + 28);

    textSize(13);
    if (playOrder[i] == 0) {
      fill(150);
      text("順番: 未設定", boxX + 15, boxY + 52);
    } else {
      fill(isPlaying ? color(100, 130, 160) : color(0, 102, 204));
      text("順番: " + playOrder[i] + " 番手", boxX + 15, boxY + 52);
    }

    int midiC = (octave + 1) * 12;
    fill(100); textSize(12);
    text("C" + octave + " = MIDI " + midiC, boxX + 15, boxY + 72);
  }

  // ----------------------------------------
  // F. 送信パケットプレビュー ＆ システム状態
  // ----------------------------------------
  fill(60); textSize(13);
  if (firstPacketSent) {
    // 2回目以降はBPMのみ3バイト
    text("次の送信パケット（3バイト BPMのみ）: " + buildBpmPacket(), 40, 585);
  } else {
    // 最初の8バイトパケット
    text("送信パケット（8バイト）: " + buildFullPacket(), 40, 585);
  }
  
  // 右下に現在のシステムステータスを表示
  textAlign(RIGHT);
  if (isPlaying) {
    fill(204, 0, 0);
    text("【ステータス: 演奏中・設定ロック中  送信#" + bpmSendCount + "/" + SCORE_ELEMENT_COUNT + "】", 760, 585);
  } else {
    fill(0, 153, 76);
    text("【ステータス: 待機中・編集可能】", 760, 585);
  }
  textAlign(LEFT); // 描画モードを左寄せに戻す
}

// ==========================================
// 3. キーボード入力
// ==========================================
void keyPressed() {
  if (key == CODED) {
    // BPM変更は演奏中（isPlaying == true）でも常に許可する
    if (keyCode == UP)   bpm = min(180, bpm + 10);
    if (keyCode == DOWN) bpm = max(30,  bpm - 10);
  }

  // 演奏順番の数字入力キーは演奏中なら無視
  if (isPlaying) return; 

  if (key >= '1' && key <= '3') { // ← '4'を'3'に変更（ドラム除く3楽器）
    int instIndex = key - '1';
    if (playOrder[instIndex] == 0 && orderCount < 3) { // ← 上限を3に変更
      orderSelection[orderCount] = instIndex;
      playOrder[instIndex] = orderCount + 1;
      orderCount++;
    }
  }
}

// ==========================================
// 4. マウスクリック
// ==========================================
void mousePressed() {
  // ① 送信ボタン（演奏中もパケット再送などのためクリックは許可）
  if (isHover(sendX, sendY, sendW, sendH)) {
    sendParametersToMaster();
    // 【シミュレーション用】シリアル未接続時は送信と同時に擬似的に演奏中フラグをtrue
    if (!isSerialConnected) {
      isPlaying = true;
      firstPacketSent = true;
      bpmSendCount = 0;
      unlockScheduledTime = -1;
      lastBpmSendTime = millis();
      println("（シミュレーション）演奏を開始しました．BPM定期送信を開始します．");
    }
  }

  // 【シミュレーション用補助コード】シリアル未接続時、's' キーで演奏停止をテストできる
  if (!isSerialConnected && key == 's') {
    isPlaying = false;
    firstPacketSent = false;
    bpmSendCount = 0;
    unlockScheduledTime = -1;
    println("（シミュレーション）演奏を手動停止しました．");
  }

  // 演奏中（isPlaying == true）なら、以下の設定変更ボタンはすべて無視（ガード処理）
  if (isPlaying) return; 

  // ② リセットボタン
  if (isHover(resetX, resetY, resetW, resetH)) {
    resetOrder();
  }

  // ③ 共通オクターブ ▲
  if (isHover(octBtnUpX, octBtnUpY, octBtnW, octBtnH)) {
    if (octave < 9) octave++;
  }

  // ④ 共通オクターブ ▼
  if (isHover(octBtnDownX, octBtnDownY, octBtnW, octBtnH)) {
    if (octave > -1) octave--;
  }
}

// ==========================================
// 5. ★【重要】Master Arduinoからの演奏開始・終了信号の受信
// ==========================================
void serialEvent(Serial myPort) {
  String inString = myPort.readStringUntil('\n'); // 改行まで読み込み
  if (inString != null) {
    inString = trim(inString); // 前後の空白・改行をカット
    
    // Masterがパケットを受け取って演奏を開始した時に送り返してくる信号
    if (inString.equals("START") || inString.equals("PLAYING")) {
      isPlaying = true;
      firstPacketSent = true;
      bpmSendCount = 0;
      unlockScheduledTime = -1;
      lastBpmSendTime = millis();
      println("【通信確認】Masterが演奏を開始しました．UIをロックします．");
    }
    
    // Master側で楽譜の演奏がすべて終了した，または緊急停止した時に送ってくる信号
    // ※通常はUI側のタイマーでロック解除するが，Masterからの信号でも解除可能
    else if (inString.equals("STOP") || inString.equals("FINISHED")) {
      isPlaying = false;
      firstPacketSent = false;
      bpmSendCount = 0;
      unlockScheduledTime = -1;
      println("【通信確認】Masterの演奏が終了しました．UIロックを解除します．");
    }
  }
}

// ==========================================
// 6. ユーティリティ関数
// ==========================================
boolean isHover(int x, int y, int w, int h) {
  return (mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h);
}

void resetOrder() {
  for (int i = 0; i < 3; i++) { // ← 3要素に変更
    playOrder[i] = 0;
    orderSelection[i] = -1;
  }
  orderCount = 0;
}

// ==========================================
// 7. 送信パケット生成
// ==========================================

// 【最初の1回】フルパケット（8バイト）
// 構造: oct(2桁) + order(3桁) + bpm(3桁) = 8バイト
// オクターブ: 国際式 -1→"00", 0→"01", 1→"02", ..., 9→"10"
// 演奏順: 3楽器分（ドラム除く），各1桁（0=未設定）
// BPM: 3桁固定（030〜180）
String buildFullPacket() {
  // オクターブ2桁：国際式 -1〜9 → 送信値 00〜10
  String octStr = nf(octave + 1, 2);

  // 演奏順3桁（ドラム除く3楽器分）
  String order = "";
  for (int i = 0; i < 3; i++) {
    order += str(playOrder[i]);
  }

  String bpmStr = nf(bpm, 3);
  return octStr + order + bpmStr; // 合計8バイト
}

// 【2回目以降】BPMのみ（3バイト）
String buildBpmPacket() {
  return nf(bpm, 3);
}

// ==========================================
// 8. Master Arduino送信関数
// ==========================================

// 最初の1回：全設定を8バイトで送信
void sendParametersToMaster() {
  String packet = buildFullPacket() + "\n";

  println("【送信パケット（初回 8バイト）】: " + packet.trim());
  println("  ├ オクターブ  : " + octave + "（国際式）→ 送信値 '" + nf(octave + 1, 2) + "'");
  println("  ├ 演奏順      : " + packet.substring(2, 5) + "  （楽器1〜3の演奏順番，ドラム除く）");
  println("  └ BPM         : " + bpm + " → '" + packet.substring(5, 8) + "'");

  if (isSerialConnected) {
    myPort.write(packet);
    println("Master Arduinoへのシリアル送信に成功しました．");
  } else {
    println("（シミュレーションモード）初回送信処理を完了しました．");
  }
  firstPacketSent = true;
}

// 演奏中のBPM定期送信（3バイトのみ）
void sendBpmOnly() {
  String packet = buildBpmPacket() + "\n";

  println("【BPM送信（3バイト）】: " + packet.trim() + "  (" + bpm + " BPM)");

  if (isSerialConnected) {
    myPort.write(packet);
  }
  // シミュレーションモードではprintlnのみ（上記で済み）
}
