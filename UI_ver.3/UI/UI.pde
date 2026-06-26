import processing.serial.*; // シリアル通信ライブラリをインポート

// ==========================================
// 1. システム制御用の変数定義
// ==========================================
Serial myPort;
boolean isSerialConnected = false; // 実機接続時はsetup内でtrueに切り替わる

int bpm = 120; // 初期BPM（30〜180）

// ドラムは演奏開始からずっと鳴り続けるため演奏順番設定から除外
String[] instNames = {"ピアノ", "フルート", "木琴"}; // 3楽器（ドラム除外）

// 各楽器の演奏順番（0:未設定，1〜3:演奏順手）
int[] playOrder = {0, 0, 0};

// オクタ/MA_ptype1/ーブは楽器共通の1変数（国際式：-1〜9）
int octave = 4;

// 演奏順番の入力管理用変数
int[] orderSelection = {-1, -1, -1};
int orderCount = 0;

// 演奏中フラグ（trueの間はBPM以外の変更をロックする）
// ロック解除はMaster Arduinoからの "FINISH" シリアル受信で行う
boolean isPlaying = false;
boolean hasSentInitialPacket = false; // 初回送信済みフラグ

BearWindow bearWin; // クマアニメーション用別ウィンドウ
boolean bearJumpKeyHeld = false;

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
  // 実機を接続する場合はコメントアウトを解除・ポート番号を合わせる
  
  try {
    String portName = "/dev/cu.usbmodem34B7DA6196202"; // 使用するポートを選択
    myPort = new Serial(this, portName, 9600);
    myPort.bufferUntil('\n'); // 改行コードが来るまでデータを溜める
    isSerialConnected = true;
  } catch (Exception e) {
    println("シリアルポートが見つかりません．シミュレーションモードで起動します．");
  }
  

  resetOrder();

  // クマアニメーションウィンドウを起動
  bearWin = new BearWindow();

  // クマの画像はメインスケッチ(this)側でloadImage()してから渡す．
  // ※ runSketch()で開く別ウィンドウ(BearWindow)内で直接loadImage()すると，
  //   セカンドアプレットのsketchPathが正しく解決されず
  //   （Processing IDEの実行ボタンでは特に発生しやすい既知の不具合），
  //   data フォルダの画像が見つからずnullになることがあるため，
  //   必ずメインスケッチ側で読み込んでから渡す．
  bearWin.bearWalk1Img  = loadImage("kuma_walk1-1.png");
  bearWin.bearWalk2Img  = loadImage("kuma_walk2-1.png");
  bearWin.bearJumpImg   = loadImage("kuma_jump2.png");
  bearWin.bearDamageImg = loadImage("kuma_damage2.png");

  // 背景・地形・障害物の画像も同様にメインスケッチ側で読み込んでから渡す
  bearWin.skyImg        = loadImage("Sky.png");
  bearWin.groundImg     = loadImage("ground.png");
  bearWin.cloudImgs[0]  = loadImage("Cloud1.png");
  bearWin.cloudImgs[1]  = loadImage("Cloud2.png");
  bearWin.treeImgs[0]   = loadImage("Tree1.png");
  bearWin.treeImgs[1]   = loadImage("Tree2.png");
  bearWin.stoneImg      = loadImage("Stone.png");

  PApplet.runSketch(new String[]{"クマアニメーション"}, bearWin);
}

void draw() {
  background(245);

  // ----------------------------------------
  // A. タイトル ＆ 送信ボタン
  // ----------------------------------------
  fill(40);
  textSize(22);
  text("ハッカソン1 グループ7 演奏制御システム", 40, 46);

  // 送信ボタン
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
  fill(isPlaying ? color(240) : color(255));
  rect(40, 185, 720, 190, 8);
  noStroke();

  fill(isPlaying ? color(140) : color(40)); textSize(16);
  text("【演奏順番の設定】" + (isPlaying ? "（演奏中：変更不可）" : ""), 60, 220);
  fill(80); textSize(14);
  text("楽器番号 ―――  1: ピアノ  |  2: フルート  |  3: 木琴  ※ドラムは常時演奏", 60, 250);

  if (isPlaying) {
    fill(200, 100, 100);
    text("★ 現在Masterが演奏中．演奏が終了するまで順番変更はできません．", 60, 275);
  } else {
    fill(0, 102, 204);
    text("★ キーボードの [1] ～ [3] キーを演奏したい順番に押してください．", 60, 275);
  }

  fill(50); textSize(14);
  text("現在の演奏ルート：", 60, 330);
  for (int i = 0; i < 3; i++) {
    int idx = orderSelection[i];
    String name = (idx == -1) ? "未選択" : instNames[idx];
    fill(idx == -1 ? color(160) : (isPlaying ? color(100, 140, 180) : color(0, 102, 204)));
    text("[" + (i + 1) + "番手: " + name + "]", 185 + i * 155, 330);
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
  fill(isPlaying ? color(240) : color(255));
  rect(40, 390, 720, 80, 8);
  noStroke();

  fill(isPlaying ? color(140) : color(40)); textSize(16);
  text("【共通オクターブ設定】" + (isPlaying ? "（演奏中：変更不可）" : ""), 60, 418);

  fill(50); textSize(14);
  String octDisplay = octave < 0 ? "-1（最低域）" : String.valueOf(octave);
  String octSendStr = nf(octave + 1, 2); // 送信用2桁値（00〜10）
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
  for (int i = 0; i < 3; i++) {
    int boxX = 40 + i * 245;
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
  text("送信パケット（8バイト）: " + buildPacket(), 40, 585);

  // 右下にシステムステータス
  textAlign(RIGHT);
  if (isPlaying) {
    fill(204, 0, 0);
    text("【ステータス: 演奏中・設定ロック中 ← Master FINISH待ち】", 760, 585);
  } else {
    fill(0, 153, 76);
    text("【ステータス: 待機中・編集可能】", 760, 585);
  }
  textAlign(LEFT);

  // クマウィンドウへBPM・演奏状態を毎フレーム同期
  if (bearWin != null) {
    bearWin.bearBpm     = bpm;
    bearWin.bearPlaying = isPlaying;
  }

  drawRunResultPanel();
}

// ==========================================
// 3. キーボード入力
// ==========================================
void keyPressed() {
  if (key == CODED) {
    // BPM変更は演奏中でも常に許可
    if (keyCode == UP)   bpm = min(180, bpm + 10);
    if (keyCode == DOWN) bpm = max(30,  bpm - 10);
  }

  if (key == ' ' && bearWin != null) {
    if (!bearJumpKeyHeld) {
      bearJumpKeyHeld = true;
      bearWin.triggerJump();
    }
  }

  if (!isSerialConnected && isPlaying && (key == 's' || key == 'S')) {
    completeCurrentRun("（シミュレーション）sキーで演奏終了しました．");
    return;
  }

  // 演奏順番の数字入力は演奏中なら無視
  if (isPlaying) return;

  if (key >= '1' && key <= '3') {
    int instIndex = key - '1';
    if (playOrder[instIndex] == 0 && orderCount < 3) {
      orderSelection[orderCount] = instIndex;
      playOrder[instIndex] = orderCount + 1;
      orderCount++;
    }
  }
}

void keyReleased() {
  if (key == ' ' && bearWin != null) {
    bearJumpKeyHeld = false;
  }
}

// ==========================================
// 4. マウスクリック
// ==========================================
void mousePressed() {
  // ① 送信ボタン
  if (isHover(sendX, sendY, sendW, sendH)) {
    sendParametersToMaster();
    // 【シミュレーション用】シリアル未接続時は擬似的にロック
    if (!isSerialConnected) {
      isPlaying = true;
      println("（シミュレーション）演奏を開始しました．");
      println("  ロック解除は Master Arduino からの 'FINISH' 受信で行われます．");
      println("  シミュレーション中に解除するには 's' キーを押してください．");
    }
  }

  // 演奏中なら以下の設定変更はすべて無視
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
// 5. Master Arduinoからのシリアル受信
// ==========================================
void serialEvent(Serial myPort) {
  String inString = myPort.readStringUntil('\n');
  if (inString != null) {
    inString = trim(inString);

    // Masterが演奏を開始した合図 → UIをロック
    if (inString.equals("START") || inString.equals("PLAYING")) {
      isPlaying = true;
      println("【通信確認】Masterが演奏を開始しました．UIをロックします．");
    }

    // Masterが演奏終了を検知した合図 → UIロックを解除
    // MA_ptype1.ino の L142: Serial.println("FINISH") に対応
    else if (inString.equals("FINISH") || inString.equals("STOP")) {
      completeCurrentRun("【通信確認】Masterから演奏終了通知（FINISH）を受信．UIロックを解除します．");
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
  for (int i = 0; i < 3; i++) {
    playOrder[i] = 0;
    orderSelection[i] = -1;
  }
  orderCount = 0;
}

void completeCurrentRun(String message) {
  isPlaying = false;
  if (bearWin != null) {
    bearWin.completeRun();
  }
  println(message);
}

void drawRunResultPanel() {
  if (bearWin == null || !bearWin.hasResult()) {
    return;
  }

  float panelX = 560;
  float panelY = 70;
  float panelW = 210;
  float panelH = 170;

  noStroke();
  fill(0, 0, 0, 160);
  rect(panelX + 4, panelY + 4, panelW, panelH, 12);
  fill(255);
  rect(panelX, panelY, panelW, panelH, 12);
  fill(40);
  textSize(16);
  text("演奏結果", panelX + 14, panelY + 14);
  textSize(13);
  text("今回の獲得コイン: " + bearWin.getCurrentRunScore(), panelX + 14, panelY + 40);
  text("ランキング", panelX + 14, panelY + 64);

  String[] lines = bearWin.getRankingLines();
  for (int i = 0; i < lines.length; i++) {
    fill(80);
    text(lines[i], panelX + 18, panelY + 86 + i * 16);
  }
}

// ==========================================
// 7. 送信パケット生成（初回のみ・8バイト固定）
// ==========================================
// 構造: oct(2桁) + order(3桁) + bpm(3桁) = 8バイト
// オクターブ: 国際式 -1〜9 → 送信値 00〜10
// 演奏順: ピアノ・フルート・木琴の3楽器分（ドラム除く）
// BPM: 030〜180の3桁固定
// ※ 2回目以降のBPM送信はMaster Arduino側が自律的に管理する
String buildPacket() {
  String octStr = nf(octave + 1, 2); // -1→"00", 0→"01", ..., 9→"10"
  String order = "";
  for (int i = 0; i < 3; i++) {
    order += str(playOrder[i]);
  }
  String bpmStr = nf(bpm, 3);
  return octStr + order + bpmStr; // 合計8バイト
}

// ==========================================
// 8. Master Arduino送信関数（初回1回のみ呼ばれる）
// ==========================================
void sendParametersToMaster() {
  if (!hasSentInitialPacket) {
    String packet = buildPacket() + "\n";

    println("【送信パケット（初回 8バイト）】: " + packet.trim());
    println("  ├ オクターブ  : " + octave + "（国際式）→ 送信値 '" + nf(octave + 1, 2) + "'");
    println("  ├ 演奏順      : " + packet.substring(2, 5) + "  （ピアノ・フルート・木琴の演奏順）");
    println("  └ BPM         : " + bpm + " → '" + packet.substring(5, 8) + "'");

    if (isSerialConnected) {
      myPort.write(packet);
      println("Master Arduinoへのシリアル送信に成功しました．");
    } else {
      println("（シミュレーションモード）初回パケット送信処理を完了しました．");
    }

    hasSentInitialPacket = true;
  } else {
    String packet = nf(bpm, 3) + "\n";

    println("【送信パケット（BPM更新 3桁）】: " + packet.trim());
    println("  └ BPM         : " + bpm + " → '" + packet.substring(0, 3) + "'");

    if (isSerialConnected) {
      myPort.write(packet);
      println("Master Arduinoへのシリアル送信に成功しました．");
    } else {
      println("（シミュレーションモード）BPM更新パケット送信処理を完了しました．");
    }
  }
}
