// ============================================================
// DrumProcessing.pde - 受信トリガー版
// SA_ptype1.ino（INST_ID==4, handleDrum()）からSerial受信 → ドラム音を再生
// 受信フォーマット：drumType,velocity,BPM
//   drumType : 1=スネア, 2=ハイハット
//   velocity : 0〜127
//   BPM      : 30〜180（参考値，Processing側では音量制御に使用）
//
// SA側はTickCountが偶数のときだけ発音するため，1回の演奏（全98Tick）で
// 鳴る回数は49回（0,2,4,...,96の49Tick）。また，SAはSTART/END等の
// ステータス文字列を送らず，デバッグ用の他の行（"I2C: ..."等）も混在して
// 送られてくるため，カンマ区切りでちょうど3項目の行だけを演奏データとして
// 扱う。
//
// 音源にはprocessing.soundではなくddf.minimを使用する
// （他のSP系ファイルと同じライブラリで，追加インストール不要）。
// ============================================================
import ddf.minim.*;
import ddf.minim.ugens.*;
import processing.serial.*;

Minim minim;
AudioOutput out;
Serial drumPort;

// ------------------------------------------------------------
// ノイズ音色クラス（スネア／ハイハット共用）
// ------------------------------------------------------------
class NoiseHit implements Instrument {
  Noise noise;
  ADSR  adsr;

  NoiseHit(float amplitude, float attack, float decay, float release) {
    noise = new Noise(amplitude, Noise.Tint.WHITE);
    adsr = new ADSR(1.0, attack, decay, 0.0, release);
    noise.patch(adsr);
  }

  void noteOn(float duration) {
    adsr.noteOn();
    adsr.patch(out);
  }

  void noteOff() {
    adsr.noteOff();
    adsr.unpatchAfterRelease(out);
  }
}

// 演奏状態
final int TOTAL_HITS = 49;    // 98Tick中，偶数Tickのみ発音するため49回
boolean isPlaying = false;
int     hitCount  = 0;
int     lastBPM   = 120;

// ------------------------------------------------------------
void setup() {
  size(400, 200);
  minim = new Minim(this);
  out   = minim.getLineOut();

  printArray(Serial.list());
  // ★ ポート番号を環境に合わせて変更
  drumPort = new Serial(this, Serial.list()[0], 9600);
  drumPort.bufferUntil('\n');
  println("DrumProcessing 起動");
}

// ------------------------------------------------------------
void draw() {
  background(20);
  fill(255);
  textSize(14);

  if (isPlaying) {
    text("演奏中... " + hitCount + " / " + TOTAL_HITS + "打", 20, 40);
    text("BPM: " + lastBPM, 20, 70);
  } else {
    text("待機中", 20, 40);
  }
}

// ------------------------------------------------------------
// Serial受信
// フォーマット：drumType,velocity,BPM
// SAはステータス文字列を送らず，デバッグ用の行も混在するため，
// カンマ区切りでちょうど3項目の行だけを演奏データとして扱う。
// ------------------------------------------------------------
void serialEvent(Serial p) {
  String line = trim(p.readStringUntil('\n'));
  if (line == null) return;

  String[] parts = split(line, ',');
  if (parts.length != 3) {
    // デバッグ行（"I2C: ..." 等）はそのままログに流すだけ
    println("[SA] " + line);
    return;
  }

  int drumType = int(parts[0]);
  float amp    = int(parts[1]) / 127.0;
  int   bpm    = int(parts[2]);
  if (bpm >= 30 && bpm <= 180) lastBPM = bpm;

  // 新しい演奏の最初の1打で状態をリセット
  if (!isPlaying) {
    isPlaying = true;
    hitCount  = 0;
  }

  // 発音
  switch (drumType) {
    case 1:
      playSnare(amp);
      println("スネア    vel=" + int(amp * 127) + " bpm=" + lastBPM);
      break;
    case 2:
      playHiHat(amp);
      println("ハイハット vel=" + int(amp * 127) + " bpm=" + lastBPM);
      break;
    default:
      println("不明なドラムタイプ: " + drumType);
      return;
  }

  hitCount++;
  if (hitCount >= TOTAL_HITS) {
    isPlaying = false;
  }
}

// ------------------------------------------------------------
void playSnare(float amp) {
  out.playNote(0.0, 0.25, new NoiseHit(amp * 1.2, 0.001, 0.04, 0.2));
}

void playHiHat(float amp) {
  out.playNote(0.0, 0.07, new NoiseHit(amp * 0.5, 0.001, 0.01, 0.05));
}

void stop() {
  minim.stop();
  super.stop();
}
