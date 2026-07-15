// ============================================================
// SlaveArduinoCanonTest.ino - T1(輪唱構造の正当性)+T2(Slave間受信同時性) 計測用Slave
//
// FINAL/SlaveArduino/SlaveArduino.ino をベースに，#ifdef CANON_TEST の
// ログ出力だけを追加したもの（TEST専用，本番では使わない）。
// 演奏ロジック（startTick / indexOffset / Tick139での収束）は本番と同一。
//
// 【出力フォーマット（CANON_TEST時）】
//   設定受信時: "CFG,<INST_ID>,<octave>,<order>,<bpm>,<startTick>"
//               （ドラムはoctave=-1, order=0, startTick=0）
//   毎Tick:     "C,<INST_ID>,<tick_id>,<score_index>,
//                <to1>,<to2>,<to3>,<dur_to>,<he1>,<he2>,<he3>,<dur_he>,<pickup_us>"
//     - tick_id     : MasterArduinoのtickCountと同じ数え方
//                     （初期設定受信=1，以後3桁Tick受信ごとに+1。i2c_latency_testと同一）
//     - score_index : このTickで参照した楽譜添字。演奏領域外（開始前・終了後）は-1。
//                     ドラムは0始まりのtickCount（発音しないTickも記録する）
//     - to*/he*     : このTickで送出した音符（ト音譜部/ヘ音譜部）。休符・非発音Tickは0。
//                     ドラムは to1=drumType, to2=velocity を流用（he側は常に0）
//     - pickup_us   : 受信割り込み開始→loop()検知の自機内所要時間（micros自己計測，T2用）
//   本番でSlave Processingへ送っていた音符データ行は，CANON_TEST時は出力しない
//   （PC側ロガー CanonTest4Port.pde が上記CSV行だけを記録するため）。
//
// 【使い方】4台のSAそれぞれに INST_ID（1=ピアノ,2=木琴,3=フルート,4=ドラム）を
// 書き換えてフラッシュする。Master ArduinoはFINAL版を無改造で使用する。
//
// 【注意】初期設定パケットの演奏順フィールドは，本番MasterProcessing(UI.pde)の
// buildPacket()が「ピアノ・フルート・木琴」の並び（index 2,3,4）で送るため，
// その並びでパースする（TEST/SlaveArduino.inoと同じ修正済みマッピング。
// FINAL/SlaveArduino.inoの「index=INST_ID+1」は木琴とフルートを取り違える）。
// ============================================================

#include <Wire.h>

#define MY_I2C_ADDRESS    0      // この楽器のI2Cアドレス（全SA共通=疑似ブロードキャスト）
#define SERIAL_BAUD       115200
#define BASE_OCTAVE       4      // 楽譜の基準オクターブ（国際式4）
#define INST_ID 3                // ピアノ=1, 木琴＝2, フルート=3, ドラム=4

#define CANON_TEST               // T1+T2計測時のみ有効化する（TEST専用）

// ドラム用定数
#define DRUM_HIHAT       2
#define DRUM_SNARE       1
#define DRUM_VEL_HIHAT   80
#define DRUM_VEL_SNARE   110

// ------------------------------------------------------------
// 楽譜データ（もりのくまさん 中級アレンジ / ト音譜部+ヘ音譜部 / 120bpm基準）
// 音階配列は各要素が3音分(和音用，未使用分は0=休符)の二次元配列。
// ------------------------------------------------------------

const int pitch_to[][3] = {
  {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {67,64,0}, {0,0,0}, {69,64,0}, {0,0,0}, {71,64,0}, {0,0,0},

  {72,67,0}, {0,0,0}, {0,0,0}, {0,0,0}, {67,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {64,60,0}, {0,0,0}, {0,0,0}, {0,0,0}, {60,0,0}, {0,0,0}, {0,0,0}, {0,0,0},

  {69,65,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {69,65,0}, {0,0,0}, {71,65,0}, {0,0,0}, {69,65,0}, {0,0,0},

  {67,65,0}, {0,0,0}, {0,0,0}, {0,0,0}, {67,66,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {69,62,0}, {0,0,0}, {0,0,0}, {0,0,0}, {71,62,0}, {0,0,0}, {0,0,0}, {0,0,0},


  {72,67,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {67,0,0}, {0,0,0}, {66,0,0}, {0,0,0}, {67,0,0}, {0,0,0},

  {64,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {64,0,0}, {0,0,0}, {63,0,0}, {0,0,0}, {64,0,0}, {0,0,0},

  {60,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {64,0,0}, {0,0,0}, {62,0,0}, {0,0,0}, {60,0,0}, {0,0,0},

  {62,0,0}, {0,0,0}, {0,0,0},{0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {67,0,0}, {0,0,0}, {69,0,0}, {0,0,0}, {67,0,0}, {0,0,0},


  {64,60,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {67,64,0}, {0,0,0}, {69,64,0}, {0,0,0}, {71,64,0}, {0,0,0},

  {72,67,0}, {0,0,0}, {0,0,0}, {0,0,0}, {67,64,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {64,60,0}, {0,0,0}, {0,0,0}, {0,0,0}, {60,0,0}, {0,0,0}, {0,0,0}, {0,0,0},

  {69,65,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {69,65,0}, {0,0,0}, {71,65,0}, {0,0,0}, {69,65,0},{0,0,0},

  {67,62,0}, {0,0,0}, {0,0,0}, {0,0,0}, {65,62,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {64,62,0}, {0,0,0}, {0,0,0}, {0,0,0}, {62,0,0}, {0,0,0}, {0,0,0}, {0,0,0},

  {60,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}
};

const int duration_to[] = {
  0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 500, 0, 0, 0,
  500, 0, 0, 0, 500, 0, 0, 0,

  1000, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 500, 0, 0, 0,
  500, 0, 0, 0, 500, 0, 0, 0,


  1000, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,


  500,0, 0, 0,  0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 500, 0, 0, 0,
  500, 0, 0, 0, 500, 0, 0, 0,

  1000, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 500, 0, 0, 0,
  500, 0, 0, 0, 500, 0, 0, 0,

  1000, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0,
};

const int pitch_he[][3] = {
  {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0}, {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0},
  {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0}, {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0},

  {48,0,0}, {0,0,0}, {60,55,0}, {0,0,0}, {48,0,0}, {0,0,0}, {60,55,0}, {0,0,0},
  {43,0,0}, {0,0,0}, {55,52,0}, {0,0,0}, {43,0,0}, {0,0,0}, {55,52,0}, {0,0,0},

  {41,0,0}, {0,0,0}, {53,48,0}, {0,0,0}, {41,0,0}, {0,0,0}, {53,48,0}, {0,0,0},
  {48,0,0}, {0,0,0}, {57,53,0}, {0,0,0}, {48,0,0}, {0,0,0}, {57,53,0}, {0,0,0},

  {47,0,0}, {0,0,0}, {57,55,0}, {0,0,0}, {47,0,0}, {0,0,0}, {57,55,0}, {0,0,0},
  {43,0,0}, {0,0,0}, {53,47,0}, {0,0,0}, {43,0,0}, {0,0,0}, {53,47,0}, {0,0,0},


  {48,0,0}, {0,0,0}, {55,0,0}, {57,0,0}, {0,0,0}, {55,0,0}, {52,0,0}, {0,0,0},
  {48,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0},

  {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0}, {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0},
  {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0}, {36,0,0}, {0,0,0}, {55,52,0}, {0,0,0},

  {48,0,0}, {0,0,0}, {60,55,0}, {0,0,0}, {48,0,0}, {0,0,0}, {60,55,0}, {0,0,0},
  {48,0,0}, {0,0,0}, {60,55,0}, {0,0,0}, {48,0,0}, {0,0,0}, {60,55,0}, {0,0,0},

  {43,0,0}, {0,0,0}, {53,50,0}, {0,0,0}, {43,0,0}, {0,0,0}, {53,50,0}, {0,0,0},
  {47,0,0}, {0,0,0}, {55,50,0}, {0,0,0}, {47,0,0}, {0,0,0}, {55,50,0}, {0,0,0},


  {48,0,0}, {0,0,0}, {55,52,0}, {0,0,0}, {48,0,0}, {0,0,0}, {55,52,0}, {0,0,0},
  {48,0,0}, {0,0,0}, {55,52,0}, {0,0,0}, {57,53,0}, {0,0,0}, {59,55,0}, {0,0,0},

  {60,52,0}, {0,0,0}, {0,0,0}, {0,0,0}, {55,48,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {48,43,0}, {0,0,0},  {0,0,0}, {0,0,0},{55,48,0}, {0,0,0}, {0,0,0}, {0,0,0},

  {41,0,0}, {0,0,0}, {45,0,0}, {0,0,0}, {48,0,0}, {0,0,0}, {53,0,0},{0,0,0},
  {57,53,48}, {0,0,0}, {0,0,0}, {0,0,0}, {45,41,0}, {0,0,0}, {0,0,0}, {0,0,0},

  {50,43,0}, {0,0,0}, {0,0,0}, {0,0,0}, {55,47,0}, {0,0,0}, {0,0,0}, {0,0,0},
  {55,50,0}, {0,0,0}, {0,0,0}, {0,0,0}, {55,53,0}, {0,0,0}, {0,0,0}, {0,0,0},

  {48,0,0}, {0,0,0}, {52,0,0}, {55,0,0}, {0,0,0}, {64,0,0}, {67,0,0}, {0,0,0},
  {72,0,0}, {0,0,0}, {0,0,0}, {0,0,0}, {48,0,0}, {0,0,0}, {0,0,0}, {0,0,0}
};

const int duration_he[] = {
  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,

  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,

  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,

  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,


  250, 0, 125, 250, 0, 125, 250, 0,
  250, 0, 0, 0, 0, 0, 0, 0,

  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,

  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,

  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,


  250, 0, 250, 0, 250, 0, 250, 0,
  250, 0, 250, 0, 250, 0, 250, 0,

  500, 0, 0, 0, 500, 0, 0, 0,
  500, 0, 0, 0, 500, 0, 0, 0,

  250, 0, 250, 0, 250, 0, 250, 0,
  500, 0, 0, 0, 500, 0, 0, 0,

  500, 0, 0, 0, 500, 0, 0, 0,
  500, 0, 0, 0, 500, 0, 0, 0,

  250, 0, 125, 250, 0, 125, 250, 0,
  250, 0, 0, 0, 500, 0, 0, 0,
};


const int SCORE_LENGTH = sizeof(pitch_to) / sizeof(pitch_to[0]);

// ------------------------------------------------------------
// グローバル変数
// ------------------------------------------------------------
volatile bool dataReceived = false;
volatile char rxBuffer[16];      // 割り込み内で受信データを保持するバッファ
volatile int  rxLength    = 0;
volatile unsigned long isrEntryUs = 0;  // 受信割り込み開始時刻（micros，pickup_us自己計測用）

int receivedOctave  = 5;      // 受信したオクターブ値
int myPlayOrder     = 1;      // 自分の演奏順（初期設定データ受信で上書きされる）
int currentBPM      = 120;    // 現在のBPM
int startTick       = 0;      // 演奏を開始するTickの閾値
int indexOffset      = -1;    // (i2cReceiveCount - startTick) からindexへの補正値
int i2cReceiveCount = 0;      // I2Cでデータを受信した回数
bool isPlaying      = false;
bool drumNextIsHihat = true;  // ドラム(INST_ID==4)用：次に鳴らす音がハイハットかどうか

#ifdef CANON_TEST
// MasterArduinoのtickCountと同じ数え方のTick番号（設定受信=1，3桁受信ごとに+1）
int canonTickId = 0;
// このTickのpickup_us（受信割り込み開始→loop検知）。loop先頭で確定させる
unsigned long canonPickupUs = 0;

// 毎Tickの挙動を1行のCSVとして出力する（フォーマットはファイル冒頭コメント参照）
void printCanonLine(int tickId, int idx,
                    int n1, int n2, int n3, long d1,
                    int m1, int m2, int m3, long d2,
                    unsigned long pickupUs) {
  Serial.print("C,");
  Serial.print(INST_ID);  Serial.print(",");
  Serial.print(tickId);   Serial.print(",");
  Serial.print(idx);      Serial.print(",");
  Serial.print(n1);       Serial.print(",");
  Serial.print(n2);       Serial.print(",");
  Serial.print(n3);       Serial.print(",");
  Serial.print(d1);       Serial.print(",");
  Serial.print(m1);       Serial.print(",");
  Serial.print(m2);       Serial.print(",");
  Serial.print(m3);       Serial.print(",");
  Serial.print(d2);       Serial.print(",");
  Serial.println(pickupUs);
}
#endif

void setup() {
  Serial.begin(SERIAL_BAUD);
  Wire.begin(MY_I2C_ADDRESS);
  Wire.onReceive(receiveEvent);
  if(INST_ID == 1) {
    Serial.println("Slave(Piano) Ready.");
  } else if (INST_ID == 2) {
    Serial.println("Slave(Mokkin) Ready.");
  } else if (INST_ID == 3) {
    Serial.println("Slave(Flute) Ready.");
  } else if(INST_ID == 4){
    Serial.println("Slave(Drum) Ready.");
  }else{
    Serial.println("Warning! Invalid instrument!");
  }
}

void loop() {
  if (dataReceived) {
#ifdef CANON_TEST
    // 受信割り込み開始→loop()検知までの受け渡し時間を自己計測（他の処理より前に確定）
    canonPickupUs = micros() - isrEntryUs;
#endif
    // 割り込みバッファの内容を，通常の String 変数にコピーして退避
    String input = "";
    for (int i = 0; i < rxLength; i++) {
      input += (char)rxBuffer[i];
    }
    dataReceived = false;
    input.trim();

#ifdef CANON_TEST
    // MasterArduino側のtickCountと同じ数え方でTick番号を維持する
    // （再生対象かどうかに関係なく，全Tickを1:1で対応付けるため）
    if (input.length() == 8) {
      canonTickId = 1;
    } else if (input.length() == 3) {
      canonTickId++;
    }
#else
    // 【デバッグ出力】I2Cで受信した生の文字列と文字数をシリアルモニタに表示
    Serial.print("I2C: ");
    Serial.println(input);
#endif

    // ドラム(INST_ID==4)は通常楽器と処理が完全に異なるため，専用関数に分岐する
    if (INST_ID == 4) {
      handleDrum(input);
      return;
    }

    // ========================================================================
    // 【判定1】初期設定データ（8桁）の受信
    // ========================================================================
    if (input.length() == 8) {
      receivedOctave = input.substring(0, 2).toInt();

      // パケット内の演奏順フィールドは「ピアノ・フルート・木琴」の並び（index 2,3,4）。
      // INST_IDの番号（ピアノ=1,木琴=2,フルート=3）とは並びが異なるため，
      // 楽器ごとに正しいフィールド位置を明示的に指定する
      // （TEST/SlaveArduino.inoと同じ修正済みマッピング）。
      int orderFieldIndex;
      if (INST_ID == 1) orderFieldIndex = 2;       // ピアノ
      else if (INST_ID == 3) orderFieldIndex = 3;  // フルート
      else if (INST_ID == 2) orderFieldIndex = 4;  // 木琴
      else orderFieldIndex = -1;                   // ドラム等（未使用）

      myPlayOrder = (orderFieldIndex >= 0)
        ? input.substring(orderFieldIndex, orderFieldIndex + 1).toInt()
        : 0;
      currentBPM = input.substring(5, 8).toInt();

      if (myPlayOrder == 1) {
        startTick = 0;
        indexOffset = -1;
      } else if (myPlayOrder == 2 || myPlayOrder == 3) {
        startTick = 81;
        indexOffset = 72;  // i2cReceiveCount==83(初回)で75要素目(index75)から始まる
      } else {
        startTick = -1;
        indexOffset = 0;
      }

      i2cReceiveCount = 0;
      isPlaying = (startTick != -1);

#ifdef CANON_TEST
      // 各SAが初期設定を正しく受信・解釈したことの記録（T1の前提確認）
      Serial.print("CFG,");
      Serial.print(INST_ID);        Serial.print(",");
      Serial.print(receivedOctave); Serial.print(",");
      Serial.print(myPlayOrder);    Serial.print(",");
      Serial.print(currentBPM);     Serial.print(",");
      Serial.println(startTick);
#else
      // 【デバッグ出力】解析した設定内容を表示
      Serial.print("  -> Config parsed. Octave:");
      Serial.print(receivedOctave);
      Serial.print(", Order:");
      Serial.print(myPlayOrder);
      Serial.print(", BPM:");
      Serial.print(currentBPM);
      Serial.print(", StartTickLimit:");
      Serial.println(startTick);
#endif
    }

    // ========================================================================
    // 【判定2】演奏中のBPMデータ（3桁）の受信 ＝ Tickカウント
    // ========================================================================
    else if (input.length() == 3) {
      currentBPM = input.toInt();

#ifdef CANON_TEST
      int  logIndex = -1;         // このTickで参照した楽譜添字（演奏領域外は-1）
      int  logTo[3] = {0, 0, 0};
      int  logHe[3] = {0, 0, 0};
      long logDurTo = 0;
      long logDurHe = 0;
#endif

      if (isPlaying) {
        i2cReceiveCount++;

        if (i2cReceiveCount > startTick) {
          int index = (i2cReceiveCount - startTick) + indexOffset;

          // myPlayOrderが2,3のときはTickCount=139（myPlayOrder==1が138要素目を演奏する
          // タイミング）から，myPlayOrder==1と同じ進行に合流する
          if ((myPlayOrder == 2 || myPlayOrder == 3) && i2cReceiveCount >= 139) {
            index = i2cReceiveCount - 1;
          }

          if (index < SCORE_LENGTH) {
            // ① pitchのオクターブ変更処理（主旋律・対旋律それぞれ，3音分）
            int targetOctave = receivedOctave - 1;

            int shiftedTo[3];
            int shiftedHe[3];
            for (int v = 0; v < 3; v++) {
              shiftedTo[v] = 0;
              if (pitch_to[index][v] > 0) {
                shiftedTo[v] = constrain(pitch_to[index][v] + (targetOctave - BASE_OCTAVE) * 12, 0, 127);
              }
              shiftedHe[v] = 0;
              if (pitch_he[index][v] > 0) {
                shiftedHe[v] = constrain(pitch_he[index][v] + (targetOctave - BASE_OCTAVE) * 12, 0, 127);
              }
            }

            // ② durationのBPM補正処理
            long targetDurationTo = (long)duration_to[index] * 120 / currentBPM;
            long targetDurationHe = (long)duration_he[index] * 120 / currentBPM;

#ifdef CANON_TEST
            logIndex = index;
            for (int v = 0; v < 3; v++) {
              logTo[v] = shiftedTo[v];
              logHe[v] = shiftedHe[v];
            }
            logDurTo = targetDurationTo;
            logDurHe = targetDurationHe;
#else
            // ③ カンマ区切りでシリアルへ送信（ト音譜部・ヘ音譜部を別の行で送信）
            Serial.print(shiftedTo[0]);
            Serial.print(",");
            Serial.print(shiftedTo[1]);
            Serial.print(",");
            Serial.print(shiftedTo[2]);
            Serial.print(",");
            Serial.println(targetDurationTo);

            Serial.print(shiftedHe[0]);
            Serial.print(",");
            Serial.print(shiftedHe[1]);
            Serial.print(",");
            Serial.print(shiftedHe[2]);
            Serial.print(",");
            Serial.println(targetDurationHe);
#endif

            if (index == SCORE_LENGTH - 1) {
              isPlaying = false;
#ifndef CANON_TEST
              // 【デバッグ出力】楽譜の最後まで演奏したことを通知
              Serial.println("  -> Score Finished.");
#endif
            }
          }
        }
      }

#ifdef CANON_TEST
      // 発音しないTick（開始前・休符・終了後）も含め，全Tickを1行ずつ記録する
      printCanonLine(canonTickId, logIndex,
                     logTo[0], logTo[1], logTo[2], logDurTo,
                     logHe[0], logHe[1], logHe[2], logDurHe,
                     canonPickupUs);
#endif
    }
  }
}

// ------------------------------------------------------------
// ドラム専用処理（INST_ID==4 のときだけ呼び出される）
// ------------------------------------------------------------
void handleDrum(String input) {
  // 【判定1】初期設定データ（8桁）の受信 → 演奏開始
  if (input.length() == 8) {
    i2cReceiveCount = 0;
    isPlaying = true;
    drumNextIsHihat = true;

#ifdef CANON_TEST
    // ドラムはoctave/orderを使わないため octave=-1, order=0 とする
    Serial.print("CFG,");
    Serial.print(INST_ID); Serial.print(",-1,0,");
    Serial.print(input.substring(5, 8).toInt());
    Serial.println(",0");
#endif
  }

  // 【判定2】演奏中のBPMデータ（3桁）の受信 ＝ Tickカウント
  else if (input.length() == 3) {
#ifdef CANON_TEST
    int logIndex = -1;   // ドラムは0始まりのtickCountを記録（演奏終了後は-1）
    int logType  = 0;    // 発音したdrumType（非発音Tickは0）
    int logVel   = 0;
#endif

    if (isPlaying) {
      i2cReceiveCount++;
      int tickCount = i2cReceiveCount - 1; // TickCountは0始まり
#ifdef CANON_TEST
      logIndex = tickCount;
#endif

      // TickCountが4の倍数のときだけ，ハイハットとスネアを交互に発音する
      if (tickCount % 4 == 0) {
        int drumType = drumNextIsHihat ? DRUM_HIHAT : DRUM_SNARE;
        int velocity = drumNextIsHihat ? DRUM_VEL_HIHAT : DRUM_VEL_SNARE;

#ifdef CANON_TEST
        logType = drumType;
        logVel  = velocity;
#else
        Serial.print(drumType);
        Serial.print(",");
        Serial.print(velocity);
        Serial.print(",");
        Serial.println(input);
#endif

        drumNextIsHihat = !drumNextIsHihat;
      }

      // TickCountが207（i2cReceiveCountが208）になったら終了
      if (tickCount == 207) {
        isPlaying = false;
      }
    }

#ifdef CANON_TEST
    // 通常楽器と同じ列構成で毎Tick記録する（to1=drumType, to2=velocity を流用）
    printCanonLine(canonTickId, logIndex,
                   logType, logVel, 0, 0,
                   0, 0, 0, 0,
                   canonPickupUs);
#endif
  }
}

// ------------------------------------------------------------
// I2C受信割り込みイベント
// ------------------------------------------------------------
void receiveEvent(int numBytes) {
  isrEntryUs = micros();  // 割り込み開始をできるだけ早く記録（pickup_us計測の起点）
  rxLength = 0;
  while (Wire.available() && rxLength < (int)sizeof(rxBuffer) - 1) {
    rxBuffer[rxLength] = Wire.read();
    rxLength++;
  }
  dataReceived = true;
}
