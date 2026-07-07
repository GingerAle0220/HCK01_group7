// ============================================================
// SP_flute.pde - フルートスレーブ Processing（音色チューニング版）
// Slave Arduino（SlaveFlute）からの ASCII テキスト
//   "MIDI,duration\n"                例: "67,250\n"（旧プロトコル）
//   "MIDI1,MIDI2,MIDI3,duration\n"   例: "67,64,0,250\n"（SA_ptype2: 3和音，0=休符）
//   "START\n" / "END\n" / "Slave(Flute) ready\n"
// を受けて Flute 音色で再生する。倍音バランスとADSRは実フルートの
// 「低音は暖かみ・高音はクリア」という特性に合わせてチューニング済み。
//
// フォールバック動作（Serial 無しでの動作確認用）:
//   - 1〜8 キー: 単音再生（PITCH_SHIFT 適用後の音域）
//   - p キー: 森のくまさん全曲
// ============================================================

import ddf.minim.*;
import ddf.minim.ugens.*;
import processing.serial.*;

Minim       minim;
AudioOutput out;
Serial      slavePort;
PFont       jpFont;

final int   BPM           = 120;
final int   DEFAULT_VEL   = 100;   // チーム仕様に velocity 無し → 固定
final float POLY_GAIN     = 0.3;   // 多重再生時のクリッピング対策（フルートはattackが長く音符が重なる）
final int   SERIAL_BAUD   = 9600;
final int   OCTAVE_UP     = 12;     // フルートは他楽器より1オクターブ高く演奏する

// ============================================================
// Flute 音色（flute_v3 と同一）
// ============================================================
int getRegister(float freq) {
  // 実フルートのレジスタに合わせる
  if (freq < 554) return 0;   // C#5以下: 低音域（warm/breathy）
  if (freq < 1109) return 1;  // C6以下: 中音域
  return 2;                    // D6以上: 高音域（pure）
}

class Flute implements Instrument {
  Oscil wave, vibrato;
  ADSR  ampEnv, breathEnv;
  Noise breath;

  Flute(float frequency, float amplitude) {
    int reg = getRegister(frequency);

    // 倍音バランス（基音, 2倍, 3倍, 4倍）。実フルートは基音支配・上倍音弱め
    // 低音は暖かみ・高音はクリアという「フルート本来の音色差」を残す
    float[][] AMPS = {
      {1.0f, 0.55f, 0.20f, 0.08f},   // 低音: 暖かみ・少しこもる（実フルートの特性）
      {1.0f, 0.40f, 0.15f, 0.05f},   // 中音: バランス
      {1.0f, 0.25f, 0.08f, 0.02f}    // 高音: クリアな純音
    };
    // ADSR: 「じわっと立ち上げて，ドロップせず保ち，滑らかにフェード」=人間の息に近い形
    float[] ATK   = {0.080f, 0.065f, 0.050f};   // ゆっくり立ち上げて「跳ね」を消す
    float[] DEC   = {0.020f, 0.015f, 0.010f};   // 一瞬で sustain へ（ドロップ感を消す）
    float[] SUS   = {0.95f,  0.95f,  0.92f };   // ピークに近い高さで保つ（body が薄くならない）
    float[] REL   = {0.150f, 0.130f, 0.110f};   // 滑らかにフェードアウト
    float[] VRATE = {5.2f,   5.2f,   5.0f  };
    float[] VDEP  = {0.0050f,0.0060f,0.0070f};
    float[] NOISE = {0.08f,  0.05f,  0.025f};   // 低音ほどブレス感（実フルート特性）

    float[] mults  = {1.0f, 2.0f, 3.0f, 4.0f};
    float[] phases = {0, 0, 0, 0};
    Waveform fluteWave = WavetableGenerator.gen9(4096, mults, AMPS[reg], phases);

    wave   = new Oscil(frequency, amplitude, fluteWave);
    ampEnv = new ADSR(amplitude, ATK[reg], DEC[reg], SUS[reg], REL[reg]);

    vibrato = new Oscil(VRATE[reg], frequency * VDEP[reg], Waves.SINE);
    Summer freqSum = new Summer();
    new Constant(frequency).patch(freqSum);
    vibrato.patch(freqSum);
    freqSum.patch(wave.frequency);
    wave.patch(ampEnv);

    breath    = new Noise(amplitude * NOISE[reg], Noise.Tint.WHITE);
    breathEnv = new ADSR(amplitude * NOISE[reg], 0.030, 0.080, 0.00, 0.050);
    breath.patch(breathEnv);
  }

  void noteOn(float duration) {
    ampEnv.noteOn();    ampEnv.patch(out);
    breathEnv.noteOn(); breathEnv.patch(out);
  }
  void noteOff() {
    ampEnv.noteOff();    ampEnv.unpatchAfterRelease(out);
    breathEnv.noteOff(); breathEnv.unpatchAfterRelease(out);
  }
}

// ============================================================
// Serial 受信で受け取った1音を再生する共通処理
// ============================================================
void playNote(int midi, int velocity, int durationMs) {
  if (midi == 0) return;  // 休符
  int shiftedMidi = constrain(midi + OCTAVE_UP, 0, 127);
  float freq = Frequency.ofMidiNote(shiftedMidi).asHz();
  float amp  = constrain(velocity / 127.0 * POLY_GAIN, 0.0, 1.0);
  float dur  = durationMs / 1000.0;  // ms → 秒
  out.playNote(0.0, dur, new Flute(freq, amp));

  println("再生 midi:" + shiftedMidi + " freq:" + nf(freq, 0, 1) + "Hz dur:" + dur + "s");
}

// ============================================================
// Serial 受信: チーム形式 ASCII "MIDI,duration\n"
// ============================================================
void serialEvent(Serial p) {
  String line = p.readStringUntil('\n');
  if (line == null) return;
  line = trim(line);
  if (line.length() == 0) return;

  // ステータスメッセージ・Slave Arduino側のデバッグログ（"I2C: 120" や
  // trim後 "-> Config parsed..." 等）は演奏データではないのでそのまま表示してスキップ
  if (line.equals("START") || line.equals("END") || line.startsWith("Slave")
      || line.startsWith("I2C:") || line.startsWith("->")) {
    println("[Slave] " + line);
    return;
  }

  // "MIDI,duration"（旧プロトコル）
  // "MIDI1,MIDI2,MIDI3,duration"（SA_ptype2: ト音/ヘ音3和音プロトコル，0=休符）
  String[] parts = split(line, ',');
  if (parts.length != 2 && parts.length != 4) return;

  try {
    int durationMs = int(parts[parts.length - 1]);
    for (int i = 0; i < parts.length - 1; i++) {
      int midi = int(parts[i]);
      playNote(midi, DEFAULT_VEL, durationMs);
    }
  } catch (Exception e) {
    // パース失敗時は何もしない（Pianoと同様，警告は出さない）
  }
}

// ============================================================
// 動作確認用フォールバック（Serial 無しでの確認）
// ============================================================
// 森のくまさん（SlaveFlute と同一: 98スロット，BPM120，全長 24.5秒）
// 1スロット = 八分音符 = 250ms
// pitch=0 は休符 or 継続スロット（duration=0）
final int SLOT_MS = 250;
final int PITCH_SHIFT = 12;  // フォールバック用 半音単位（+12=1オクターブ上=C5-C6, +7=完全5度, +5=完全4度, 0=元のまま）

int[] testPitch = {
  // slot 0-15
   0, 67, 69, 71, 72,  0, 67,  0, 64,  0, 60,  0, 69,  0,  0,  0,
  // slot 16-31
   0, 69, 71, 69, 67,  0, 68,  0, 69,  0, 71,  0, 72,  0,  0,  0,
  // slot 32-47
   0, 67, 66, 67, 64,  0,  0,  0,  0, 64, 63, 64, 60,  0,  0,  0,
  // slot 48-63
   0, 64, 62, 60, 62,  0,  0,  0,  0, 67, 69, 67, 64,  0,  0,  0,
  // slot 64-79
   0, 67, 69, 71, 72,  0, 67,  0, 64,  0, 60,  0, 69,  0,  0,  0,
  // slot 80-95
   0, 69, 71, 69, 67,  0, 65,  0, 64,  0, 62,  0, 60,  0,  0,  0,
  // slot 96-97
   0,  0
};

int[] testDurationMs = {
  // slot 0-15
     0, 250, 250, 250, 500,   0, 500,   0, 500,   0, 500,   0,1000,   0,   0,   0,
  // slot 16-31
     0, 250, 250, 250, 500,   0, 500,   0, 500,   0, 500,   0,1000,   0,   0,   0,
  // slot 32-47
     0, 250, 250, 250,1000,   0,   0,   0,   0, 250, 250, 250,1000,   0,   0,   0,
  // slot 48-63
     0, 250, 250, 250,1000,   0,   0,   0,   0, 250, 250, 250,1000,   0,   0,   0,
  // slot 64-79
     0, 250, 250, 250, 500,   0, 500,   0, 500,   0, 500,   0,1000,   0,   0,   0,
  // slot 80-95
     0, 250, 250, 250, 500,   0, 500,   0, 500,   0, 500,   0,1500,   0,   0,   0,
  // slot 96-97
     0,   0
};

void playSongFallback() {
  out.pauseNotes();
  for (int i = 0; i < testPitch.length; i++) {
    if (testPitch[i] == 0) continue;  // 休符 or 継続スロット
    float f   = Frequency.ofMidiNote(testPitch[i] + PITCH_SHIFT).asHz();
    float t   = (i * SLOT_MS) / 1000.0;        // スロット番号 × 250ms → 秒
    float dur = testDurationMs[i] / 1000.0;
    out.playNote(t, dur, new Flute(f, 0.5));
  }
  out.resumeNotes();
}

// ============================================================
// setup / draw
// ============================================================
void setup() {
  size(640, 240);
  minim = new Minim(this);
  out   = minim.getLineOut();
  // Minimのplayote(start,dur,...)は「拍」で解釈される。
  // tempo=60にして1拍=1秒にすることで，ms÷1000で渡した値がそのまま秒として再生される。
  out.setTempo(60);
  
  printArray(Serial.list());
  // ★ ポート番号を環境に合わせて変更
  slavePort = new Serial(this, Serial.list()[3], 9600);
  slavePort.bufferUntil('\n');

  println("SlaveProcessing（フルート）起動");
}

void draw() {
  background(0);
  fill(255);
  textSize(14);
  text("フルート受信待機中...", 20, 185);

  stroke(255);
  for (int i = 0; i < out.bufferSize() - 1; i++) {
    line(i, 120 - out.left.get(i)*60,  i+1, 120 - out.left.get(i+1)*60);
    line(i, 200 - out.right.get(i)*60, i+1, 200 - out.right.get(i+1)*60);
  }
}

void keyPressed() {
  if (key == 'p') { playSongFallback(); return; }
  int idx = key - '1';
  if (idx >= 0 && idx < 8) {
    int[] scaleMidi = {60, 62, 64, 65, 67, 69, 71, 72};  // C4〜C5
    float f = Frequency.ofMidiNote(scaleMidi[idx] + PITCH_SHIFT).asHz();
    out.playNote(0.0, 1.0, new Flute(f, 0.5));
  }
}
