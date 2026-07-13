// ============================================================
// BearWindow.pde — クマアニメーション用の別ウィンドウ
// BPMでスクロール速度を変え，コイン収集・障害物回避・ランキング表示を行う．
// ============================================================

class BearWindow extends PApplet {

  // UI.pde 側から毎フレーム書き込まれる
  float   bearBpm     = 120.0;
  boolean bearPlaying = false;

  final float BASE_BPM        = 120.0;
  final float BASE_SPEED      = 4.0;
  final float GRAVITY         = 0.9;
  final float JUMP_VELOCITY   = -14.5;
  final int   MAX_JUMPS       = 2;
  final float BEAR_X          = 210.0;
  final float BEAR_GROUND_Y   = 250.0;
  final int   COIN_COUNT       = 7;
  final int   OBSTACLE_COUNT   = 4;
  final int   SCATTER_COUNT    = 36;
  final int   RANKING_SIZE     = 5;

  // ----------------------------------------
  // クマ画像（ドット絵）
  // ----------------------------------------
  PImage bearWalk1Img;
  PImage bearWalk2Img;
  PImage bearJumpImg;
  PImage bearDamageImg;

  // ----------------------------------------
  // 背景・地形・障害物の画像（ドット絵）
  // ----------------------------------------
  PImage skyImg;
  PImage groundImg;
  PImage[] cloudImgs = new PImage[2];   // Cloud1, Cloud2
  PImage[] treeImgs  = new PImage[2];   // Tree1, Tree2
  PImage stoneImg;

  // 地面ベルトのスクロール位置（groundImgを横に敷き詰めてループさせる）
  float groundScrollX = 0;

  // 地面の表示高さ（groundTop()からキャンバス下端まで埋める）
  final float GROUND_DISPLAY_H = 120.0;

  // 地面タイルを敷き詰める際，サブピクセルの丸め誤差で縦線（隙間）が
  // 見えないようにするための1pxオーバーラップ量
  final float GROUND_TILE_OVERLAP = 1.0;

  // 画面に表示する際のクマの高さ（幅はアスペクト比から自動算出）
  final float BEAR_DISPLAY_H = 110.0;

  // 画像の足元を実際の地面ラインに合わせるための補正値
  // （元のクマ描画ではBEAR_GROUND_Yが地面ライン(groundTop)より少し上にあったため，
  //   画像の接地位置も同じだけ地面寄りに補正する）
  final float BEAR_FOOT_OFFSET = 65.0;

  // 木・石（障害物）も同様に，地面ラインに対する見た目の接地位置を調整する補正値．
  // 値を大きくするほど画像が下（地面の奥）にずれ，小さくする（負の値も可）ほど上にずれる．
  final float TREE_FOOT_OFFSET     = 35.0;
  final float OBSTACLE_FOOT_OFFSET = 40.0;

  // 当たり判定（画像中心に置く円形ヒットボックス）の半径
  // 見た目の画像サイズより少し小さめにして，当たり判定をフェアにする
  final float BEAR_HIT_RADIUS = 30.0;

  // クマの状態（見た目の切り替え用）
  final int BEAR_STATE_WALK   = 0;
  final int BEAR_STATE_JUMP   = 1;
  final int BEAR_STATE_DAMAGE = 2;
  int bearState = BEAR_STATE_WALK;

  float legAngle = 0;
  float bearJumpY = 0;
  float bearJumpV = 0;
  int jumpsRemaining = MAX_JUMPS;
  boolean jumpKeyHeld = false;

  int currentRunScore = 0;
  int bestScore = 0;
  int currentRank = -1;
  int collectFlash = 0;
  int hitFlash = 0;
  int finishFlash = 0;
  int collisionCooldown = 0;
  int runSerial = 0;
  boolean runStarted = false;
  boolean runFinished = false;
  boolean lastPlayingState = false;

  float[] treeX = new float[4];
  float[] cloudX = new float[3];
  int[] treeType = new int[4];   // 0=Tree1, 1=Tree2
  int[] cloudType = new int[3];  // 0=Cloud1, 1=Cloud2

  float[] coinX = new float[COIN_COUNT];
  float[] coinY = new float[COIN_COUNT];
  float[] coinSpin = new float[COIN_COUNT];

  float[] obstacleX = new float[OBSTACLE_COUNT];
  float[] obstacleY = new float[OBSTACLE_COUNT];
  float[] obstacleScale = new float[OBSTACLE_COUNT];

  float[] scatterX = new float[SCATTER_COUNT];
  float[] scatterY = new float[SCATTER_COUNT];
  float[] scatterVX = new float[SCATTER_COUNT];
  float[] scatterVY = new float[SCATTER_COUNT];
  float[] scatterSpin = new float[SCATTER_COUNT];
  int[] scatterLife = new int[SCATTER_COUNT];
  boolean[] scatterActive = new boolean[SCATTER_COUNT];
  int scatterCursor = 0;

  int[] rankingScores = new int[RANKING_SIZE];

  void settings() {
    // P2D（GPUレンダラー）にすることで，JAVA2D（デフォルト）特有の
    // フレームレートの揺れ・カクつきが起きにくくなる．
    // ※ 実行環境でOpenGLが使えずエラーになる場合は，
    //   size(800, 400); （P2D指定を外す）に戻してください．
    size(800, 400, P2D);
  }

  void setup() {
    textAlign(LEFT, TOP);

    // フレームレートを明示的に固定し，動きを滑らかにする
    frameRate(60);

    // クマ画像・背景画像（空，地面，雲，木，石）はすべて
    // メインスケッチ(UI.pde)側でloadImage()され，
    // bearWin.bearWalk1Img / skyImg / groundImg / cloudImgs[] / treeImgs[] / stoneImg
    // などに代入されてからここに来る想定．
    // ※ PApplet.runSketch()で起動するセカンドウィンドウは，
    //   sketchPath()がスケッチフォルダではなくProcessing本体側を指す
    //   既知の不具合があり，ここで直接loadImage()すると
    //   IDEの実行ボタンからは画像が見つからずnullになることがある．
    //   そのためここでは読み込まず，メインスケッチから渡された画像を使う．

    for (int i = 0; i < 4; i++) {
      treeX[i] = i * 250;
      treeType[i] = int(random(2));
    }
    for (int i = 0; i < 3; i++) {
      cloudX[i] = i * 300 + 50;
      cloudType[i] = int(random(2));
    }
    resetCoins();
    resetObstacles();
    clearScatter();
  }

  void draw() {
    if (bearPlaying && !lastPlayingState) {
      startRun(bearBpm);
    }

    updateWorld();

    // 背景（空・地面）
    drawSky();
    drawGround();

    // 描画
    noStroke();
    for (int i = 0; i < 3; i++) drawCloud(cloudX[i], 80 + (i % 2) * 40, cloudType[i]);
    for (int i = 0; i < 4; i++) drawTree(treeX[i], 280, treeType[i]);
    for (int i = 0; i < COIN_COUNT; i++) drawCoin(coinX[i], coinY[i], coinSpin[i]);
    for (int i = 0; i < OBSTACLE_COUNT; i++) drawObstacle(i);
    drawScatter();
    drawBear(BEAR_X, BEAR_GROUND_Y + bearJumpY, legAngle);
    drawHud();

    if (runFinished) {
      drawResultPanel();
    } else if (bearPlaying) {
      drawBpmBanner();
    }
  }

  void updateWorld() {
    float speed = getScrollSpeed();
    float obstacleSpeed = speed * 1.08;

    for (int i = 0; i < 3; i++) {
      cloudX[i] -= speed * 0.2;
      if (cloudX[i] < -100) {
        cloudX[i] = width + 100;
        cloudType[i] = int(random(2));
      }
    }
    for (int i = 0; i < 4; i++) {
      treeX[i] -= speed;
      if (treeX[i] < -100) {
        treeX[i] = width + random(80, 180);
        treeType[i] = int(random(2));
      }
    }

    updateJump();
    updateCoins(speed);
    updateObstacles(obstacleSpeed);
    updateScatter();

    // 地面ベルトのスクロール（タイル間隔(画像幅-オーバーラップ)で循環させる）
    if (groundImg != null) {
      groundScrollX += speed * 0.6;
      float tileStep = groundImg.width - GROUND_TILE_OVERLAP;
      if (tileStep > 0) {
        groundScrollX = ((groundScrollX % tileStep) + tileStep) % tileStep;
      }
    }

    if (collectFlash > 0) collectFlash--;
    if (hitFlash > 0) hitFlash--;
    if (finishFlash > 0) finishFlash--;
    if (collisionCooldown > 0) collisionCooldown--;

    if (bearPlaying) {
      legAngle += speed * 0.05;
    }

    updateBearState();

    lastPlayingState = bearPlaying;
  }

  // クマの見た目の状態（歩行／ジャンプ／ダメージ）を更新する
  void updateBearState() {
    if (hitFlash > 0) {
      bearState = BEAR_STATE_DAMAGE;
    } else if (bearJumpY < 0) {
      bearState = BEAR_STATE_JUMP;
    } else {
      bearState = BEAR_STATE_WALK;
    }
  }

  float getScrollSpeed() {
    if (runFinished) {
      return 0;
    }
    float bpmScale = max(0.6, bearBpm / BASE_BPM);
    // 一番右の「BASE_SPEED * 0.35」を「0」にする
    return bearPlaying ? BASE_SPEED * bpmScale : 0;
  }

  void updateCoins(float speed) {
    boolean gameplayActive = runStarted && !runFinished;
    for (int i = 0; i < COIN_COUNT; i++) {
      coinX[i] -= speed;
      coinSpin[i] += speed * 0.06;
      if (coinX[i] < -40) {
        respawnCoin(i, width + random(140, 280));
      }
      if (gameplayActive && isCoinCollected(i)) {
        currentRunScore++;
        bestScore = max(bestScore, currentRunScore);
        collectFlash = 18;
        spawnScatter(coinX[i], coinY[i], 6, true);
        respawnCoin(i, width + random(180, 320));
      }
    }
  }

  void updateObstacles(float speed) {
    boolean gameplayActive = runStarted && !runFinished;
    for (int i = 0; i < OBSTACLE_COUNT; i++) {
      obstacleX[i] -= speed;
      if (obstacleX[i] < -120) {
        respawnObstacle(i, nextObstacleSpawnX(i));
      }
    }

    if (!gameplayActive || collisionCooldown > 0) {
      return;
    }

    for (int i = 0; i < OBSTACLE_COUNT; i++) {
      if (isObstacleHit(i)) {
        applyObstaclePenalty(i);
        collisionCooldown = 18;
        break;
      }
    }
  }

  void applyObstaclePenalty(int i) {
    int penalty = 2;
    currentRunScore = max(0, currentRunScore - penalty);
    hitFlash = 24;
    finishFlash = 0;
    float bearBurstX = BEAR_X + 18;
    float bearBurstY = BEAR_GROUND_Y + bearJumpY - 12;
    spawnScatter(bearBurstX, bearBurstY, 16 + penalty * 4, true);
    respawnObstacle(i, width + random(160, 280));
  }

  // クマをドット絵画像で描画する．
  // x, y は「地面に立っている時の足元中心」（既存のBEAR_X, BEAR_GROUND_Y + bearJumpYに対応）．
  void drawBear(float x, float y, float angle) {
    PImage img = currentBearImage(angle);
    if (img == null) return;

    float dispH = BEAR_DISPLAY_H;
    float dispW = dispH * (float(img.width) / float(img.height));
    float footY = y + BEAR_FOOT_OFFSET;

    // 画像下端を足元(footY)に，左右中央をxに合わせて描画する
    imageMode(CORNER);
    image(img, x - dispW / 2.0, footY - dispH, dispW, dispH);
  }

  // 現在の状態に応じて表示する画像を返す
  PImage currentBearImage(float angle) {
    switch (bearState) {
      case BEAR_STATE_JUMP:
        return bearJumpImg;
      case BEAR_STATE_DAMAGE:
        return bearDamageImg;
      default:
        // 歩行アニメーション：legAngleの位相で2枚のコマを切り替える
        return (sin(angle) >= 0) ? bearWalk1Img : bearWalk2Img;
    }
  }

  // クマの当たり判定（画像の中心）の座標を返す．
  // 当たり判定はビジュアルとは独立したオブジェクトとして，
  // 画像の中心点 + 半径 BEAR_HIT_RADIUS の円で扱う．
  float bearHitCenterX() {
    return BEAR_X;
  }

  float bearHitCenterY() {
    return BEAR_GROUND_Y + bearJumpY + BEAR_FOOT_OFFSET - BEAR_DISPLAY_H / 2.0;
  }

  // 空：キャンバス全体に伸縮表示する静的背景
  void drawSky() {
    if (skyImg != null) {
      imageMode(CORNER);
      image(skyImg, 0, 0, width, height);
    } else {
      background(135, 206, 235);
    }
  }

  // 地面：groundImgを横に敷き詰めてスクロールさせる
  void drawGround() {
    float top = groundTop();
    if (groundImg == null) {
      noStroke();
      fill(34, 139, 34);
      rect(0, top, width, height - top);
      return;
    }

    imageMode(CORNER);
    float gw = groundImg.width;
    float tileStep = gw - GROUND_TILE_OVERLAP;
    // groundScrollXを起点に，画面の左端より1タイル手前から右端を覆うまで敷き詰める
    float startX = -groundScrollX - gw;
    for (float x = startX; x < width; x += tileStep) {
      image(groundImg, round(x), top, gw, GROUND_DISPLAY_H);
    }
  }

  void drawCloud(float x, int y, int type) {
    PImage img = cloudImgs[constrain(type, 0, cloudImgs.length - 1)];
    if (img == null) return;
    float dispW = 100;
    float dispH = dispW * (float(img.height) / float(img.width));
    imageMode(CORNER);
    image(img, x, y, dispW, dispH);
  }

  void drawTree(float x, float groundY, int type) {
    PImage img = treeImgs[constrain(type, 0, treeImgs.length - 1)];
    if (img == null) return;
    float dispH = 150;
    float dispW = dispH * (float(img.width) / float(img.height));
    imageMode(CORNER);
    // 木の根元をgroundY + TREE_FOOT_OFFSETに合わせる
    float footY = groundY + TREE_FOOT_OFFSET;
    image(img, x, footY - dispH, dispW, dispH);
  }

  void drawCoin(float x, float y, float spin) {
    pushMatrix();
    translate(x, y);
    float squash = 0.55 + 0.45 * abs(sin(spin));
    scale(squash, 1);
    stroke(170, 120, 0);
    strokeWeight(2);
    fill(255, 214, 0);
    ellipse(0, 0, 28, 28);
    noStroke();
    fill(255, 245, 160, 180);
    ellipse(-4, -5, 8, 8);
    popMatrix();
  }

  void drawObstacle(int i) {
    drawRock(obstacleX[i], obstacleY[i] + OBSTACLE_FOOT_OFFSET, obstacleScale[i]);
  }

  void drawRock(float x, float y, float s) {
    if (stoneImg == null) {
      pushMatrix();
      translate(x, y);
      scale(s);
      fill(120);
      stroke(90);
      strokeWeight(2);
      beginShape();
      vertex(6, 34);
      vertex(0, 18);
      vertex(8, 4);
      vertex(26, 0);
      vertex(38, 8);
      vertex(40, 24);
      vertex(28, 36);
      endShape(CLOSE);
      noStroke();
      fill(155);
      ellipse(16, 14, 11, 8);
      popMatrix();
      return;
    }

    // 当たり判定(obstacleWidth/Height)と見た目のサイズを一致させて画像を描画する
    pushMatrix();
    translate(x, y);
    imageMode(CORNER);
    image(stoneImg, 0, 0, obstacleBaseWidth() * s, obstacleBaseHeight() * s);
    popMatrix();
  }

  void drawScatter() {
    for (int i = 0; i < SCATTER_COUNT; i++) {
      if (!scatterActive[i]) continue;
      float alpha = map(scatterLife[i], 0, 26, 0, 220);
      pushMatrix();
      translate(scatterX[i], scatterY[i]);
      rotate(scatterSpin[i]);
      stroke(170, 120, 0, alpha);
      strokeWeight(1.5);
      fill(255, 214, 0, alpha);
      ellipse(0, 0, 12, 12);
      noStroke();
      fill(255, 245, 160, alpha);
      ellipse(-2, -2, 3, 3);
      popMatrix();
    }
  }

  void drawHud() {
    fill(0, 0, 0, 115);
    rect(14, 12, 190, 66, 10);
    fill(255);
    textSize(15);
    text("COINS  " + currentRunScore, 28, 22);
    text("BPM    " + nf(bearBpm, 0, 0), 28, 42);
    text("BEST   " + bestScore, 28, 60);

    if (collectFlash > 0) {
      fill(255, 240, 120, 220);
      textSize(18);
      text("GET!", 690, 18);
    }

    if (hitFlash > 0) {
      fill(255, 216, 96, 230);
      textSize(16);
      text("COINS!", 690, 42);
    }
  }

  void drawBpmBanner() {
    fill(0, 0, 0, 105);
    rect(560, 12, 216, 30, 8);
    fill(255);
    textSize(14);
    text("BPM " + nf(bearBpm, 0, 0) + "  /  speed x" + nf(getScrollSpeed() / BASE_SPEED, 0, 2), 575, 18);
  }

  void drawResultPanel() {
    fill(0, 0, 0, 165);
    rect(420, 44, 350, 190, 14);
    fill(255);
    textSize(18);
    text("FINISH", 442, 58);
    textSize(14);
    text("RUN SCORE  " + currentRunScore, 442, 88);
    text("BEST SCORE " + bestScore, 442, 108);
    text("RANKING", 442, 136);

    String[] lines = getRankingLines();
    textSize(13);
    for (int i = 0; i < lines.length; i++) {
      fill(i == currentRank ? color(255, 240, 120) : color(255));
      text(lines[i], 458, 156 + i * 16);
    }
  }

  void updateJump() {
    if (bearJumpY < 0 || bearJumpV != 0) {
      bearJumpV += GRAVITY;
      bearJumpY += bearJumpV;
      if (bearJumpY >= 0) {
        bearJumpY = 0;
        bearJumpV = 0;
        jumpsRemaining = MAX_JUMPS;
      }
    }
  }

  boolean isCoinCollected(int i) {
    float bearCenterX = bearHitCenterX();
    float bearCenterY = bearHitCenterY();
    return dist(coinX[i], coinY[i], bearCenterX, bearCenterY) < (BEAR_HIT_RADIUS + 4);
  }

  boolean isObstacleHit(int i) {
    float bearCenterX = bearHitCenterX();
    float bearCenterY = bearHitCenterY();
    return circleRectOverlap(bearCenterX, bearCenterY, BEAR_HIT_RADIUS,
                              obstacleX[i], obstacleY[i], obstacleWidth(i), obstacleHeight(i));
  }

  boolean rectsOverlap(float ax, float ay, float aw, float ah, float bx, float by, float bw, float bh) {
    return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
  }

  // 円（クマの当たり判定）と矩形（障害物）の衝突判定
  boolean circleRectOverlap(float cx, float cy, float r, float rx, float ry, float rw, float rh) {
    float closestX = constrain(cx, rx, rx + rw);
    float closestY = constrain(cy, ry, ry + rh);
    float dx = cx - closestX;
    float dy = cy - closestY;
    return (dx * dx + dy * dy) < (r * r);
  }

  float obstacleBaseWidth() {
    return 44;
  }

  float obstacleBaseHeight() {
    return 32;
  }

  float obstacleWidth(int i) {
    return obstacleBaseWidth() * obstacleScale[i];
  }

  float obstacleHeight(int i) {
    return obstacleBaseHeight() * obstacleScale[i];
  }

  float groundTop() {
    return 280;
  }

  float nextObstacleSpawnX(int i) {
    float bpmScale = constrain((bearBpm - 60.0) / 120.0, 0.0, 1.0);
    float minGap = lerp(270, 150, bpmScale);
    float maxGap = lerp(400, 220, bpmScale);
    return width + random(minGap, maxGap) + i * random(20, 50);
  }

  void respawnCoin(int i, float x) {
    coinX[i] = x;
    coinY[i] = random(150, 230);
    coinSpin[i] = random(TWO_PI);
  }

  void resetCoins() {
    float x = width + 60;
    for (int i = 0; i < COIN_COUNT; i++) {
      coinX[i] = x + i * 130 + random(30, 110);
      coinY[i] = random(150, 230);
      coinSpin[i] = random(TWO_PI);
    }
  }

  void resetObstacles() {
    float x = width + 120;
    for (int i = 0; i < OBSTACLE_COUNT; i++) {
      respawnObstacle(i, x + i * 220 + random(80, 140));
    }
  }

  void respawnObstacle(int i, float x) {
    obstacleScale[i] = random(0.95, 1.25);
    obstacleX[i] = x;
    obstacleY[i] = groundTop() - obstacleHeight(i);
  }

  void clearScatter() {
    for (int i = 0; i < SCATTER_COUNT; i++) {
      scatterActive[i] = false;
      scatterLife[i] = 0;
    }
    scatterCursor = 0;
  }

  void updateScatter() {
    for (int i = 0; i < SCATTER_COUNT; i++) {
      if (!scatterActive[i]) continue;
      scatterX[i] += scatterVX[i];
      scatterY[i] += scatterVY[i];
      scatterVX[i] *= 0.985;
      scatterVY[i] += 0.22;
      scatterSpin[i] += 0.18 + abs(scatterVX[i]) * 0.02;
      scatterLife[i]--;
      if (scatterLife[i] <= 0 || scatterY[i] > height + 40 || scatterX[i] < -40 || scatterX[i] > width + 40) {
        scatterActive[i] = false;
      }
    }
  }

  void spawnScatter(float x, float y, int amount, boolean fromCoin) {
    for (int n = 0; n < amount; n++) {
      int i = scatterCursor;
      scatterCursor = (scatterCursor + 1) % SCATTER_COUNT;
      scatterActive[i] = true;
      scatterX[i] = x + random(-8, 8);
      scatterY[i] = y + random(-8, 8);
      float spread = fromCoin ? random(2.0, 4.8) : random(2.8, 6.4);
      float angle = fromCoin ? random(TWO_PI) : random(-PI, PI);
      scatterVX[i] = cos(angle) * spread;
      scatterVY[i] = sin(angle) * spread - random(1.5, 5.0);
      scatterSpin[i] = random(TWO_PI);
      scatterLife[i] = fromCoin ? 18 : 26;
    }
  }

  void startRun(float bpm) {
    bearBpm = bpm;
    runStarted = true;
    runFinished = false;
    currentRunScore = 0;
    currentRank = -1;
    collectFlash = 0;
    hitFlash = 0;
    finishFlash = 0;
    collisionCooldown = 0;
    legAngle = 0;
    bearJumpY = 0;
    bearJumpV = 0;
    jumpsRemaining = MAX_JUMPS;
    jumpKeyHeld = false;
    resetCoins();
    resetObstacles();
    clearScatter();
    runSerial++;
  }

  void completeRun() {
    if (!runStarted) {
      startRun(bearBpm);
    }
    if (runFinished) {
      return;
    }
    runFinished = true;
    bearPlaying = false;
    finishFlash = 60;
    currentRank = insertRanking(currentRunScore);
  }

  int insertRanking(int score) {
    int rank = -1;
    for (int i = 0; i < RANKING_SIZE; i++) {
      if (score >= rankingScores[i]) {
        rank = i;
        break;
      }
    }

    if (rank == -1) {
      bestScore = max(bestScore, score);
      return -1;
    }

    for (int i = RANKING_SIZE - 1; i > rank; i--) {
      rankingScores[i] = rankingScores[i - 1];
    }
    rankingScores[rank] = score;
    bestScore = max(bestScore, rankingScores[0]);
    return rank;
  }

  String[] getRankingLines() {
    String[] lines = new String[RANKING_SIZE];
    for (int i = 0; i < RANKING_SIZE; i++) {
      if (rankingScores[i] == 0 && i > 0 && rankingScores[i - 1] == 0) {
        lines[i] = (i + 1) + ". --";
      } else {
        lines[i] = (i + 1) + ". " + rankingScores[i];
      }
    }
    return lines;
  }

  boolean hasResult() {
    return runFinished;
  }

  int getCurrentRunScore() {
    return currentRunScore;
  }

  void triggerJump() {
    if (runFinished || jumpsRemaining <= 0) {
      return;
    }
    bearJumpV = JUMP_VELOCITY;
    jumpsRemaining--;
  }

  void keyPressed() {
    if (key == ' ' && !jumpKeyHeld) {
      jumpKeyHeld = true;
      triggerJump();
    }
  }

  void keyReleased() {
    if (key == ' ') {
      jumpKeyHeld = false;
    }
  }
}
