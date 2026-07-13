import processing.serial.*; // シリアル通信ライブラリをインポート

// ==========================================
// 1. システム制御用の変数定義
// ==========================================
Serial myPort;
boolean isSerialConnected = false; // 実機接続時はsetup内でtrueに切り替わる

int bpm = 120; // 初期BPM（30〜180）

// 0=選択画面, 1=子ども, 2=大人
int appMode = 0;

// ドラムは演奏開始からずっと鳴り続けるため演奏順番設定から除外
String[] instNames = {"ピアノ", "フルート", "木琴"}; // 3楽器（ドラム除外）
String[] childInstNames = {"ピアノ", "フルート", "もっきん"};

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
int resetX = 610, resetY = 230, resetW = 120, resetH = 40;
int childModeX = 210, childModeY = 260, childModeW = 160, childModeH = 72;
int adultModeX = 430, adultModeY = 260, adultModeW = 160, adultModeH = 72;

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
    String portName = Serial.list()[3];; // 使用するポートを選択
    myPort = new Serial(this, portName, 115200);
    myPort.bufferUntil('\n'); // 改行コードが来るまでデータを溜める
    isSerialConnected = true;
  } catch (Exception e) {
    println("シリアルポートが見つかりません．シミュレーションモードで起動します．");
  }
  

  resetOrder();
}

void draw() {
  if (appMode == 0) {
    drawModeSelectScreen();
    return;
  }

  boolean childMode = appMode == 1;
  background(childMode ? color(255, 252, 232) : color(245));

  // ----------------------------------------
  // A. タイトル ＆ 送信ボタン
  // ----------------------------------------
  fill(childMode ? color(36, 92, 140) : color(40));
  textSize(childMode ? 24 : 22);
  text(childMode ? "みんなで えんそうしよう" : "ハッカソン1 グループ7 演奏制御システム", 40, 46);

  // 送信ボタン
  boolean isSendHovered = isHover(sendX, sendY, sendW, sendH);
  fill(isSendHovered ? (childMode ? color(255, 137, 42) : color(0, 153, 76)) : (childMode ? color(255, 177, 66) : color(0, 204, 102)));
  stroke(isSendHovered ? (childMode ? color(230, 96, 20) : color(0, 102, 51)) : (childMode ? color(245, 130, 32) : color(0, 153, 76)));
  strokeWeight(isSendHovered ? 2 : 1);
  rect(sendX, sendY, sendW, sendH, 6);
  noStroke();
  fill(255);
  textSize(childMode ? 17 : 14);
  text(childMode ? "はじめる！" : "設定確定・送信", sendX + (childMode ? 38 : 26), sendY + 21);

  // ----------------------------------------
  // B. BPM設定エリア（演奏中も変更可能）
  // ----------------------------------------
  stroke(childMode ? color(255, 190, 80) : color(200));
  fill(childMode ? color(255, 255, 250) : color(255));
  rect(40, 75, 720, 90, 8);
  noStroke();

  fill(childMode ? color(36, 92, 140) : color(40));
  textSize(childMode ? 24 : 20);
  text((childMode ? "テンポ（はやさ）: " : "現在の設定BPM: ") + bpm, 60, 115);
  fill(childMode ? color(92, 122, 145) : color(120));
  textSize(childMode ? 15 : 13);
  text(childMode ? "【そうさ】[↑] キーで はやく / [↓] キーで ゆっくり（30〜180）※えんそうちゅうも かえられます" : "【操作方法】[↑] キーで +10 / [↓] キーで -10（範囲：30〜180）※演奏中も可変", 60, 145);

  // ----------------------------------------
  // C. 演奏順番設定エリア（演奏中はロック）
  // ----------------------------------------
  stroke(childMode ? color(114, 202, 255) : color(200));
  fill(isPlaying ? (childMode ? color(245, 248, 250) : color(240)) : (childMode ? color(252, 255, 255) : color(255)));
  rect(40, 185, 720, 190, 8);
  noStroke();

  fill(isPlaying ? color(140) : (childMode ? color(36, 92, 140) : color(40)));
  textSize(childMode ? 18 : 16);
  text((childMode ? "【えんそうのじゅんばん】" : "【演奏順番の設定】") + (isPlaying ? (childMode ? "（えんそうちゅう：かえられません）" : "（演奏中：変更不可）") : ""), 60, 220);
  fill(childMode ? color(75, 93, 110) : color(80));
  textSize(childMode ? 16 : 14);
  text(childMode ? "がっきのばんごう ――  1: ピアノ  |  2: フルート  |  3: もっきん  ※ドラムはいつも なります" : "楽器番号 ―――  1: ピアノ  |  2: フルート  |  3: 木琴  ※ドラムは常時演奏", 60, 250);

  if (isPlaying) {
    fill(200, 100, 100);
    text(childMode ? "★ いま えんそうちゅうです。おわるまで じゅんばんは かえられません。" : "★ 現在Masterが演奏中．演奏が終了するまで順番変更はできません．", 60, 275);
  } else {
    fill(childMode ? color(20, 128, 210) : color(0, 102, 204));
    text(childMode ? "★ キーボードの [1] ～ [3] キーを、ならしたい じゅんばんに おしてね。" : "★ キーボードの [1] ～ [3] キーを演奏したい順番に押してください．", 60, 275);
  }

  fill(50);
  textSize(childMode ? 16 : 14);
  text(childMode ? "いまの えんそうルート：" : "現在の演奏ルート：", 60, 330);
  int routeStartX = childMode ? 235 : 185;
  int routeGap = 155;
  int routeArrowOffset = 115;
  for (int i = 0; i < 3; i++) {
    int idx = orderSelection[i];
    String name = (idx == -1) ? (childMode ? "まだ" : "未選択") : (childMode ? childInstNames[idx] : instNames[idx]);
    fill(idx == -1 ? color(160) : (isPlaying ? color(100, 140, 180) : (childMode ? color(20, 128, 210) : color(0, 102, 204))));
    text("[" + (i + 1) + (childMode ? "ばん: " : "番手: ") + name + "]", routeStartX + i * routeGap, 330);
    if (i < 2) { fill(180); text("→", routeStartX + routeArrowOffset + i * routeGap, 330); }
  }

  // 順番リセットボタン（演奏中はグレー）
  int resetButtonY = getResetButtonY();
  if (isPlaying) {
    fill(230); stroke(200);
    rect(resetX, resetButtonY, resetW, resetH, 6); noStroke();
    fill(160); textSize(14);
    text(childMode ? "まってね" : "ロック中", resetX + (childMode ? 28 : 32), resetButtonY + 25);
  } else {
    boolean isResetHovered = isHover(resetX, resetButtonY, resetW, resetH);
    fill(isResetHovered ? (childMode ? color(255, 235, 120) : color(255, 210, 210)) : (childMode ? color(255, 246, 170) : color(255, 235, 235)));
    stroke(isResetHovered ? (childMode ? color(235, 172, 20) : color(204, 0, 0)) : (childMode ? color(240, 196, 45) : color(255, 150, 150)));
    rect(resetX, resetButtonY, resetW, resetH, 6); noStroke();
    fill(childMode ? color(145, 103, 0) : color(204, 0, 0));
    textSize(childMode ? 16 : 14);
    text(childMode ? "やりなおす" : "順番リセット", resetX + (childMode ? 22 : 18), resetButtonY + 25);
  }

  // ----------------------------------------
  // D. 共通オクターブ設定エリア（演奏中はロック）
  // ----------------------------------------
  stroke(childMode ? color(156, 215, 93) : color(180));
  fill(isPlaying ? (childMode ? color(245, 248, 240) : color(240)) : (childMode ? color(253, 255, 247) : color(255)));
  rect(40, 390, 720, 80, 8);
  noStroke();

  fill(isPlaying ? color(140) : (childMode ? color(65, 120, 55) : color(40)));
  textSize(childMode ? 18 : 16);
  text((childMode ? "【おとのたかさ】" : "【共通オクターブ設定】") + (isPlaying ? (childMode ? "（えんそうちゅう：かえられません）" : "（演奏中：変更不可）") : ""), 60, 418);

  fill(50);
  textSize(childMode ? 16 : 14);
  String octDisplay = octave < 0 ? "-1（最低域）" : String.valueOf(octave);
  String octSendStr = nf(octave + 1, 2); // 送信用2桁値（00〜10）
  text(childMode ? "いまの おとのたかさ: " + octave + "  （おくるすうじ: " + octSendStr + "）" : "現在のオクターブ: " + octDisplay + "  （送信値: " + octSendStr + "）  （国際式 -1〜9）", 60, 448);

  // ▲ ボタン（演奏中は非活性）
  if (isPlaying) {
    fill(235); stroke(220); rect(octBtnUpX, octBtnUpY, octBtnW, octBtnH, 4); noStroke();
    fill(170); textSize(14); text("▲ +1", octBtnUpX + 7, octBtnUpY + 22);
  } else {
    boolean isUpHover = isHover(octBtnUpX, octBtnUpY, octBtnW, octBtnH);
    fill(isUpHover ? (childMode ? color(218, 245, 255) : color(215, 235, 255)) : color(245));
    stroke(isUpHover ? (childMode ? color(20, 128, 210) : color(0, 102, 204)) : color(210));
    rect(octBtnUpX, octBtnUpY, octBtnW, octBtnH, 4); noStroke();
    fill(40); textSize(14); text("▲ +1", octBtnUpX + 7, octBtnUpY + 22);
  }

  // ▼ ボタン（演奏中は非活性）
  if (isPlaying) {
    fill(235); stroke(220); rect(octBtnDownX, octBtnDownY, octBtnW, octBtnH, 4); noStroke();
    fill(170); textSize(14); text("▼ -1", octBtnDownX + 7, octBtnDownY + 22);
  } else {
    boolean isDownHover = isHover(octBtnDownX, octBtnDownY, octBtnW, octBtnH);
    fill(isDownHover ? (childMode ? color(218, 245, 255) : color(215, 235, 255)) : color(245));
    stroke(isDownHover ? (childMode ? color(20, 128, 210) : color(0, 102, 204)) : color(210));
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

    stroke(childMode ? color(168, 190, 255) : color(200));
    fill(childMode ? color(255, 255, 252) : color(255));
    rect(boxX, boxY, boxW, boxH, 8);
    noStroke();

    fill(childMode ? color(55, 72, 135) : color(40));
    textSize(childMode ? 17 : 15);
    text((childMode ? childInstNames[i] : instNames[i]) + " (" + (i + 1) + ")", boxX + 15, boxY + 28);

    textSize(childMode ? 15 : 13);
    if (playOrder[i] == 0) {
      fill(150);
      text(childMode ? "じゅんばん: まだ" : "順番: 未設定", boxX + 15, boxY + 52);
    } else {
      fill(isPlaying ? color(100, 130, 160) : (childMode ? color(20, 128, 210) : color(0, 102, 204)));
      text((childMode ? "じゅんばん: " : "順番: ") + playOrder[i] + (childMode ? " ばん" : " 番手"), boxX + 15, boxY + 52);
    }

    int midiC = (octave + 1) * 12;
    fill(100); textSize(12);
    text("C" + octave + " = MIDI " + midiC, boxX + 15, boxY + 72);
  }

  // ----------------------------------------
  // F. 送信パケットプレビュー ＆ システム状態
  // ----------------------------------------
  fill(60);
  textSize(childMode ? 14 : 13);
  text((childMode ? "おくるすうじ: " : "送信パケット（8バイト）: ") + buildPacket(), 40, 585);

  // 右下にシステムステータス
  textAlign(RIGHT);
  if (isPlaying) {
    fill(204, 0, 0);
    text(childMode ? "【いまのじょうたい: えんそうちゅう・まってね】" : "【ステータス: 演奏中・設定ロック中 ← Master FINISH待ち】", 760, 585);
  } else {
    fill(0, 153, 76);
    text(childMode ? "【いまのじょうたい: じゅんびOK】" : "【ステータス: 待機中・編集可能】", 760, 585);
  }
  textAlign(LEFT);

  // クマウィンドウへBPM・演奏状態を毎フレーム同期
  if (bearWin != null) {
    bearWin.bearBpm     = bpm;
    bearWin.bearPlaying = isPlaying;
  }

  // ランキングはクマアニメーション画面だけに表示する。
}

// ==========================================
// 3. キーボード入力
// ==========================================
void keyPressed() {
  if (appMode == 0) return;

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
  if (appMode == 0) return;

  if (key == ' ' && bearWin != null) {
    bearJumpKeyHeld = false;
  }
}

// ==========================================
// 4. マウスクリック
// ==========================================
void mousePressed() {
  if (appMode == 0) {
    if (isHover(childModeX, childModeY, childModeW, childModeH)) {
      appMode = 1;
      startBearWindow();
    } else if (isHover(adultModeX, adultModeY, adultModeW, adultModeH)) {
      appMode = 2;
      startBearWindow();
    }
    return;
  }

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
  if (isHover(resetX, getResetButtonY(), resetW, resetH)) {
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

int getResetButtonY() {
  return appMode == 1 ? resetY + 32 : resetY;
}

void drawModeSelectScreen() {
  background(255, 252, 232);

  noStroke();
  fill(216, 233, 255);
  ellipse(135, 120, 120, 120);
  fill(224, 244, 225);
  ellipse(655, 120, 120, 120);
  fill(244, 220, 239);
  ellipse(135, 430, 120, 120);
  fill(225, 232, 250);
  ellipse(655, 430, 120, 120);

  fill(36, 92, 140);
  textAlign(CENTER);
  textSize(34);
  text("だれが つかうの？", width / 2, 170);
  textSize(18);
  fill(92, 122, 145);
  text("えらんでから えんそうの じゅんびを します", width / 2, 210);

  drawModeButton(childModeX, childModeY, childModeW, childModeH, "こども", color(255, 177, 66), color(255, 137, 42));
  drawModeButton(adultModeX, adultModeY, adultModeW, adultModeH, "大人", color(0, 204, 102), color(0, 153, 76));

  textAlign(LEFT);
}

void drawModeButton(int x, int y, int w, int h, String label, int baseColor, int hoverColor) {
  boolean hovered = isHover(x, y, w, h);
  fill(hovered ? hoverColor : baseColor);
  stroke(hovered ? color(90) : color(255));
  strokeWeight(hovered ? 3 : 2);
  rect(x, y, w, h, 12);
  noStroke();
  fill(255);
  textAlign(CENTER, CENTER);
  textSize(28);
  text(label, x + w / 2, y + h / 2 - 2);
  textAlign(LEFT, BASELINE);
}

void startBearWindow() {
  if (bearWin != null) return;

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

  boolean childMode = appMode == 1;
  float panelX = 560;
  float panelY = 70;
  float panelW = 210;
  float panelH = 170;

  noStroke();
  fill(0, 0, 0, 160);
  rect(panelX + 4, panelY + 4, panelW, panelH, 12);
  fill(255);
  rect(panelX, panelY, panelW, panelH, 12);
  fill(childMode ? color(36, 92, 140) : color(40));
  textSize(childMode ? 18 : 16);
  text(childMode ? "えんそうのけっか" : "演奏結果", panelX + 14, panelY + 14);
  textSize(childMode ? 14 : 13);
  text((childMode ? "もらったコイン: " : "今回の獲得コイン: ") + bearWin.getCurrentRunScore(), panelX + 14, panelY + 40);
  text(childMode ? "じゅんい" : "ランキング", panelX + 14, panelY + 64);

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
