import processing.serial.*;

// ==========================================
// 1. システム制御用の変数定義
// ==========================================
Serial myPort;
boolean isSerialConnected = false;

int bpm = 120;

// 【変更】3楽器（ピアノ=0, 木琴=1, フルート=2）に対応
String[] instNames = {"ピアノ", "木琴", "フルート"};

// 各楽器の演奏順番（0:未設定，1〜3:演奏順）
int[] playOrder = {0, 0, 0};

// オクターブ（国際式：-1〜9）
int octave = 4;

// 演奏順番の入力管理
int[] orderSelection = {-1, -1, -1};
int orderCount = 0;

// 演奏中フラグ
boolean isPlaying = false;

// 楽譜要素数（29音）→ isPlayingの解除カウントに使用
final int SCORE_LENGTH    = 29;   // Slaveの楽譜配列サイズに同期
final int MAX_START_COUNT = 38;   // 後半グループの開始Tick数(38回目から演奏)
final int PLAY_LIMIT      = SCORE_LENGTH + MAX_START_COUNT;
int sendCount = 0;

// ==========================================
// 2. UIボタン配置用座標
// ==========================================
int sendX = 610, sendY = 20, sendW = 150, sendH = 32;
int resetX = 610, resetY = 220, resetW = 120, rectH = 40; // 変数名をrectHからresetHに変更してエラーを防止
int resetH = 40;

int octBtnUpX, octBtnUpY;
int octBtnDownX, octBtnDownY;
int octBtnW = 50, octBtnH = 32;

void setup() {
  size(800, 550); // 楽器数が3台に増えたため、縦幅を少し広げました
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

  octBtnUpX   = 440;
  octBtnUpY   = 370;
  octBtnDownX = 510;
  octBtnDownY = 370;

  // シリアル通信の初期設定
  try {
    printArray(Serial.list());
    // 環境に合わせて Serial.list()[番号] の位置を調整してください
    myPort = new Serial(this, Serial.list()[3], 9600);
    myPort.bufferUntil('\n');
    isSerialConnected = true;
  } catch (Exception e) {
    println("シリアルポートが見つかりません．シミュレーションモードで起動します．");
  }

  resetOrder();
}

void draw() {
  background(245);

  // ----------------------------------------
  // A. タイトル ＆ 送信ボタン
  // ----------------------------------------
  fill(40);
  textSize(22);
  text("ハッカソン1 グループ7 演奏制御システム", 40, 46);

  boolean isSendHovered = isHover(sendX, sendY, sendW, sendH);
  fill(isSendHovered ? color(0, 153, 76) : color(0, 204, 102));
  stroke(isSendHovered ? color(0, 102, 51) : color(0, 153, 76));
  strokeWeight(isSendHovered ? 2 : 1);
  rect(sendX, sendY, sendW, sendH, 6);
  noStroke();
  fill(255); textSize(14);
  text("設定確定・送信", sendX + 26, sendY + 21);

  // ----------------------------------------
  // B. BPM設定エリア
  // ----------------------------------------
  stroke(200); fill(255);
  rect(40, 75, 720, 80, 8);
  noStroke();

  fill(40); textSize(20);
  text("現在の設定BPM: " + bpm, 60, 110);
  fill(120); textSize(13);
  text("【操作方法】[↑] キーで +10 / [↓] キーで -10（範囲：30〜180）※演奏中も可変", 60, 140);

  // ----------------------------------------
  // C. 演奏順番設定エリア
  // ----------------------------------------
  stroke(200);
  fill(isPlaying ? color(240) : color(255));
  rect(40, 170, 720, 150, 8);
  noStroke();

  fill(isPlaying ? color(140) : color(40)); textSize(16);
  text("【演奏順番の設定】" + (isPlaying ? "（演奏中：変更不可）" : ""), 60, 200);
  fill(80); textSize(14);
  text("楽器番号 ―――  1: ピアノ  |  2: 木琴  |  3: フルート", 60, 225);

  if (isPlaying) {
    fill(200, 100, 100);
    text("★ 現在演奏中．演奏が終了するまで順番変更はできません．", 60, 248);
  } else {
    fill(0, 102, 204);
    text("★ キーボードの [1] [2] [3] キーを演奏したい順番に押してください．", 60, 248);
  }

  fill(50); textSize(14);
  text("現在の演奏ルート：", 60, 290);
  for (int i = 0; i < 3; i++) {
    int idx = orderSelection[i];
    String name = (idx == -1) ? "未選択" : instNames[idx];
    fill(idx == -1 ? color(160) : (isPlaying ? color(100, 140, 180) : color(0, 102, 204)));
    text("[" + (i + 1) + "番手: " + name + "]", 180 + i * 150, 290);
    if (i < 2) { fill(180); text("→", 310 + i * 150, 290); }
  }

  // リセットボタン
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
  // D. 共通オクターブ設定エリア
  // ----------------------------------------
  stroke(180);
  fill(isPlaying ? color(240) : color(255));
  rect(40, 340, 720, 80, 8);
  noStroke();

  fill(isPlaying ? color(140) : color(40)); textSize(16);
  text("【共通オクターブ設定】" + (isPlaying ? "（演奏中：変更不可）" : ""), 60, 368);

  fill(50); textSize(14);
  String octLabel = (octave == -1) ? "-1（最低域）" : String.valueOf(octave);
  text("現在のオクターブ: " + octLabel + " （国際式 -1〜9）", 60, 395);

  // ▲ボタン
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

  // ▼ボタン
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
  // E. 各楽器ステータスボックス（3台分に拡張）
  // ----------------------------------------
  for (int i = 0; i < 3; i++) {
    int boxX = 40 + i * 190;
    int boxY = 440;
    int boxW = 175;
    int boxH = 65;

    stroke(200); fill(255);
    rect(boxX, boxY, boxW, boxH, 8);
    noStroke();

    fill(40); textSize(14);
    text(instNames[i] + " (" + (i + 1) + ")", boxX + 12, boxY + 24);

    textSize(12);
    if (playOrder[i] == 0) {
      fill(150);
      text("順番: 未設定", boxX + 12, boxY + 44);
    } else {
      fill(isPlaying ? color(100, 130, 160) : color(0, 102, 204));
      text("順番: " + playOrder[i] + " 番手", boxX + 12, boxY + 44);
    }

    int midiC = (octave + 1) * 12;
    fill(100); textSize(11);
    text("C" + octave + " = MIDI " + midiC, boxX + 12, boxY + 58);
  }

  // ----------------------------------------
  // F. 送信パケットプレビュー ＆ ステータス
  // ----------------------------------------
  fill(60); textSize(13);
  text("送信パケット（8バイト）: " + buildPacket(), 40, 535);

  textAlign(RIGHT);
  if (isPlaying) {
    fill(204, 0, 0);
    text("【ステータス: 演奏中・設定ロック中】", 760, 535);
  } else {
    fill(0, 153, 76);
    text("【ステータス: 待機中・編集可能】", 760, 535);
  }
  textAlign(LEFT);
}

// ==========================================
// 3. キーボード入力（キー操作時は内部変数のみ変更）
// ==========================================
void keyPressed() {
  if (key == CODED) {
    if (keyCode == UP) {
      bpm = min(180, bpm + 10);
      // ★ 演奏中の即時送信（myPort.write）の処理を削除しました。
      // これにより、キーを押した段階では画面の表示BPMが変わるだけになります。
    }
    if (keyCode == DOWN) {
      bpm = max(30,  bpm - 10);
      // ★ 演奏中の即時送信（myPort.write）の処理を削除しました。
    }
  }

  // 演奏中はこれ以降の「演奏順番キー（1〜3キー）」の入力を受け付けない
  if (isPlaying) return;

  // 1〜3キーで演奏順を設定（3楽器分）
  if (key >= '1' && key <= '3') {
    int instIndex = key - '1';
    if (playOrder[instIndex] == 0 && orderCount < 3) {
      orderSelection[orderCount] = instIndex;
      playOrder[instIndex] = orderCount + 1;
      orderCount++;
    }
  }
}

// ==========================================
// 4. マウスクリック（送信ボタンで状況に応じたパケットを送信）
// ==========================================
void mousePressed() {
  // --- 「設定確定・送信」ボタンが押されたとき ---
  if (isHover(sendX, sendY, sendW, sendH)) {
    
    if (!isPlaying) {
      // A. まだ演奏していない（待機中）場合 ➔ いつもの「8桁初期設定パケット」を送信
      sendParametersToMaster();
      
      if (!isSerialConnected) {
        isPlaying  = true;
        sendCount  = 0;
        println("（シミュレーション）演奏を開始しました．");
      }
    } else {
      // B. すでに演奏中の場合 ➔ 変更されたBPMを「3桁の同期パケット」として送信
      if (isSerialConnected) {
        String shortBpmPacket = nf(bpm, 3) + "\n";
        myPort.write(shortBpmPacket);
        println("【演奏中BPM変更・送信ボタン実行】: " + shortBpmPacket.trim());
      } else {
        println("（シミュレーション演奏中）BPMを " + bpm + " に変更しました．");
      }
    }
  }

  // 演奏中は、以下の「順番リセット」や「オクターブ変更」のボタン操作を受け付けない
  if (isPlaying) return;

  if (isHover(resetX, resetY, resetW, resetH)) resetOrder();

  if (isHover(octBtnUpX, octBtnUpY, octBtnW, octBtnH)) {
    if (octave < 9) octave++;
  }
  if (isHover(octBtnDownX, octBtnDownY, octBtnW, octBtnH)) {
    if (octave > -1) octave--;
  }
}

// ==========================================
// 5. Masterからの信号受信
// ==========================================
void serialEvent(Serial p) {
  String inString = p.readStringUntil('\n');
  if (inString == null) return;
  inString = trim(inString);

  // Arduinoから届いた生ログをProcessingのコンソールに流す（デバッグ用）
  println("[Master Arduino]: " + inString); 

  if (inString.equals("START")) { 
    isPlaying  = true;
    println("【演奏開始】Master Arduinoが再生を始めました。UIをロックします。");
  }
  
  // ★【重要】Master Arduinoから完全に演奏が終わった合図が届いたらロック解除
  else if (inString.equals("FINISH")) {
    isPlaying  = false;
    println("【演奏終了】Master Arduinoから終了合図を受信。UIロックを解除しました。");
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

// ==========================================
// 7. 送信パケット生成（新仕様：8桁の文字列固定長）
// 上2桁オクターブ（00〜10）+ 演奏順3桁（ピアノ/木琴/フルート）+ BPM3桁
// ==========================================
String buildPacket() {
  // ① オクターブ：-1を00、0を01、... 9を10とする（2桁の数字文字列にフォーマット）
  int optOctave = octave + 1;
  String octStr = nf(optOctave, 2);

  // ② 演奏順（3桁：ピアノの順番、木琴の順番、フルートの順番）
  String order = "";
  for (int i = 0; i < 3; i++) {
    order += str(playOrder[i]);
  }

  // ③ BPM（3桁）
  String bpmStr = nf(bpm, 3);
  
  // 計 2桁 + 3桁 + 3桁 ＝ 8桁
  return octStr + order + bpmStr;
}

// ==========================================
// 8. Master Arduino送信関数
// ==========================================
void sendParametersToMaster() {
  String packet = buildPacket();

  println("【送信パケット】: " + packet);
  println("  ├ オクターブ(上2桁) : " + packet.substring(0, 2) + " (元の値: " + octave + ")");
  println("  ├ 演奏順(中3桁)     : " + packet.substring(2, 5) + " (ピ/木/フ)");
  println("  └ BPM(下3桁)        : " + packet.substring(5, 8) + " (" + bpm + ")");

  if (isSerialConnected) {
    myPort.write(packet); // 末尾に改行 \n を付与して送信
  } else {
    println("（シミュレーションモード）");
  }
}
