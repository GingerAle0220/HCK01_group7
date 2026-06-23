// ============================================================================
// Slave Arduino - ピアノ担当 (コンパイルエラー修正版)
// ============================================================================

#include <Wire.h>

#define MY_I2C_ADDRESS    0      // この楽器のI2Cアドレス
#define SERIAL_BAUD       9600
#define BASE_OCTAVE       4      // 楽譜の基準オクターブ（国際式4）

// ----------------------------------------------------------------------------
// 楽譜データ（もりのくまさん / ピアノ主旋律 / 120bpm基準）
// ----------------------------------------------------------------------------

const int pitch[] = {
  0,  67, 69, 71, 72, 67, 64, 60, 69,
  0,  69, 71, 69, 67, 65, 64, 62, 60,
  0,  67, 66, 67, 64,  0,  0, 64, 63, 64, 50
};

const int duration[] = {
  250, 250, 250, 250, 500, 500, 500, 500, 1000,
  250, 250, 250, 250, 500, 500, 500, 500, 1000,
  250, 250, 250, 250, 500, 500,
  250, 250, 250, 250, 500, 500, 250
};

const int SCORE_LENGTH = sizeof(pitch) / sizeof(pitch[0]);

// ----------------------------------------------------------------------------
// グローバル変数
// ----------------------------------------------------------------------------
volatile bool dataReceived = false;
volatile String rxString   = ""; // 割り込み内で使うため volatile は維持

int receivedOctave  = 5;      // 受信したオクターブ値
int myPlayOrder     = 1;      // 自分の演奏順
int currentBPM      = 120;    // 現在のBPM
int startTick       = 0;      // 演奏を開始するTickの閾値
int i2cReceiveCount = 0;      // I2Cでデータを受信した回数
bool isPlaying      = false;

void setup() {
  Serial.begin(SERIAL_BAUD);
  Wire.begin(MY_I2C_ADDRESS);
  Wire.onReceive(receiveEvent);
  Serial.println("Slave(Piano) Ready.");
}

void loop() {
  if (dataReceived) {
    // ★【重要】volatile変数の内容を、通常の String 変数にコピーして退避
    // これにより、以降の String 操作や Serial.print でエラーが出なくなります
    String input = String((const String&)rxString); 
    dataReceived = false;

    // 【デバッグ出力】I2Cで受信した生の文字列と文字数をシリアルモニタに表示
    Serial.print("I2C: ");
    Serial.println(input);

    // ========================================================================
    // 【判定1】初期設定データ（8桁）の受信
    // ========================================================================
    if (input.length() == 8) {
      receivedOctave = input.substring(0, 2).toInt();
      myPlayOrder = input.substring(2, 3).toInt(); // ピアノはインデックス2番目
      currentBPM = input.substring(5, 8).toInt();

      if (myPlayOrder == 1) {
        startTick = 0;  
      } else if (myPlayOrder == 2 || myPlayOrder == 3) {
        startTick = 37; 
      } else {
        startTick = -1; 
      }

      i2cReceiveCount = 0;
      isPlaying = (startTick != -1);
      
      // 【デバッグ出力】解析した設定内容を表示
      Serial.print("  -> Config parsed. Octave:");
      Serial.print(receivedOctave);
      Serial.print(", Order:");
      Serial.print(myPlayOrder);
      Serial.print(", BPM:");
      Serial.print(currentBPM);
      Serial.print(", StartTickLimit:");
      Serial.println(startTick);
    }
    
    // ========================================================================
    // 【判定2】演奏中のBPMデータ（3桁）の受信 ＝ Tickカウント
    // ========================================================================
    else if (input.length() == 3) {
      currentBPM = input.toInt();
      
      if (isPlaying) {
        i2cReceiveCount++; 

        if (i2cReceiveCount > startTick) {
          int tickCount = i2cReceiveCount - startTick;
          int index = tickCount - 1;

          if (index < SCORE_LENGTH) {
            // ① pitchのオクターブ変更処理
            int targetOctave = receivedOctave - 1;
            int shiftedPitch = 0;
            
            if (pitch[index] > 0) {
              shiftedPitch = pitch[index] + (targetOctave - BASE_OCTAVE) * 12;
              shiftedPitch = constrain(shiftedPitch, 0, 127);
            }

            // ② durationのBPM補正処理
            long targetDuration = (long)duration[index] * 120 / currentBPM;

            // ③ カンマ区切りでシリアルモニタへ送信
            Serial.print(shiftedPitch);
            Serial.print(",");
            Serial.println(targetDuration);

            if (index == SCORE_LENGTH - 1) {
              isPlaying = false;
              // 【デバッグ出力】楽譜の最後まで演奏したことを通知
              Serial.println("  -> Score Finished.");
            }
          }
        }
      }
    }
  }
}

// ----------------------------------------------------------------------------
// I2C受信割り込みイベント
// ----------------------------------------------------------------------------
void receiveEvent(int numBytes) {
  rxString = "";
  while (Wire.available()) {
    char c = Wire.read();
    rxString += c;
  }
  rxString.trim();
  dataReceived = true;
}