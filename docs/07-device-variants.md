# 07. 機種差分

> **この文書が答える問い**: AtomCam / AtomSwing / WyzeCamV3 で、コードのどこがどう分岐するのか？
> **前提として読む文書**: [03. 起動シーケンス](./03-boot-sequence.md), [04. libcallback による機能注入](./04-libcallback-injection.md)
> **関連する既存文書**: [`../libcallback/libcallback_hook.md`](../libcallback/libcallback_hook.md)（機種限定コマンドの注記）

本書は**横断参照テーブル**である。他の文書（03/04/06）から機種差分を引くときの辞書として使う。通読は不要。

---

## 1. 機種識別 — PRODUCT_MODEL

すべての機種分岐の起点は `/atom/configs/.product_config` の `PRODUCT_MODEL` である。これを起動系（`S61atomcam`, `atom_init.sh`, `wyze_init.sh`）と libcallback（`command.c`）の双方が読む。

| PRODUCT_MODEL | 機種 | 内部フラグ |
|---|---|---|
| `ATOM_CAKP1JZJP` | AtomSwing（pan/tilt モータ付き） | `swing=1`（[`../libcallback/command.c:228`](../libcallback/command.c)） |
| `WYZE_CAKP2JFUS` | WyzeCam V3 | `wyze=1`（[`../libcallback/command.c:227`](../libcallback/command.c)） |
| `AC1` / `ATOM_CamV3C` | dongle_app 系（[`../overlay_rootfs/atom_patch/system_bin/atom_init.sh:35`](../overlay_rootfs/atom_patch/system_bin/atom_init.sh)） | ― |
| 上記以外 | AtomCam / AtomCam2 等 | `wyze=0, swing=0` |

libcallback 側では `command.c` の constructor がこの値を読んで `wyze` / `swing` グローバルを設定し、各モジュールが `extern` で参照して分岐する（[04. libcallback による機能注入](./04-libcallback-injection.md) の 2 章）。

---

## 2. 機種差分マトリクス

| 項目 | AtomCam / 無印 | AtomSwing (`swing`) | WyzeCam V3 (`wyze`) |
|---|---|---|---|
| 起動バイナリ | `iCamera_app` | `iCamera_app` | **`iCamera`**（[`wyze_init.sh:49`](../overlay_rootfs/atom_patch/system_bin/wyze_init.sh)） |
| 起動スクリプト | `atom_init.sh` | `atom_init.sh` | `wyze_init.sh`（`S61atomcam:49-53` で分岐） |
| `audio.ko` 引数 | `spk_gpio=-1` | `spk_gpio=-1 alc_mode=0 mic_gain=0` | `spk_gpio=-1 alc_mode=0 mic_gain=0` |
| `avpu.ko` | 既定 | 既定 | ubootddr が 540MHz なら `clk_name='mpll' avpu_clk=540000000`（[`wyze_init.sh:18-23`](../overlay_rootfs/atom_patch/system_bin/wyze_init.sh)） |
| モータドライバ | ― | `sample_motor.ko`（[`atom_init.sh:27`](../overlay_rootfs/atom_patch/system_bin/atom_init.sh)） | ― |
| 追加デーモン | ― | ― | `syslogd` / `sinker`（[`wyze_init.sh:37,48`](../overlay_rootfs/atom_patch/system_bin/wyze_init.sh)） |
| 映像 ch 構成 | 3ch（video0 H264/1080, video1 HEVC/640×360, video2 HEVC/1080） | 同左 | 2ch（video0 H264/1080, video1 H264/**640×320**） |
| 音声レート | 8000Hz | 8000Hz | **16000Hz** |
| pan/tilt 追尾 | 無効 | **有効**（`motor.c` / `wait_motion.c` / `gmtime_r.c`） | 無効 |
| クルーズ | ― | **有効**（`cruise.sh`） | ― |
| curl アラーム URL | `/device/v1/alarm/add` | 同左 | `/device/alarm/upload_alarm`（[04](./04-libcallback-injection.md) の `curl.c`） |
| alarmConfig 機能 | ― | ― | **有効**（`alarmConfig` コマンド、`alarm_config.c`） |
| `mp4write` の snprintf フック | 不要 | 不要 | **必要**（start_handler 後の path 再設定対策、[`../libcallback/libcallback_hook.md`](../libcallback/libcallback_hook.md) の `mp4write.c`） |

映像 ch 数や音声レートは libcallback の `video_callback.c` / `audio_callback.c` が `wyze` フラグで分岐する。追尾系のうち `motor.c`（`:45`）と `wait_motion.c`（`:37`）は `swing` 以外では「error」を返して無効化され、`gmtime_r.c` は非 swing 機種では追尾中の AI 無効化ロジックをスキップして通常の `gmtime_r` の結果をそのまま返す。

---

## 3. libcallback における機種分岐の実装パターン

各モジュールは次のように `extern` グローバルを参照して分岐する。

```c
extern int wyze;    // command.c で定義（WYZE_CAKP2JFUS で 1）
extern int swing;   // command.c で定義（ATOM_CAKP1JZJP で 1）

// 例: 音声チャンネル数の切替
int chNum = wyze ? 2 : 3;

// 例: curl アラーム URL の切替
const char *alarmPath = wyze ? AlarmPathWyze : AlarmPathAtom;   // curl.c:135
```

`alarm_config.c` は Wyze と Atom で alarmConfig テーブルのサイズが異なるため、`memset` フック内でサイズを見てどちらのテーブルかを判別する（[04](./04-libcallback-injection.md) の技法③）。

---

## 4. 新機種を追加する場合のチェックリスト

1. **機種識別**: `.product_config` の `PRODUCT_MODEL` 値を確認し、必要なら `command.c` の constructor（[`../libcallback/command.c:225-228`](../libcallback/command.c)）にフラグ判定を追加。
2. **起動分岐**: [`../overlay_rootfs/etc/init.d/S61atomcam:49-53`](../overlay_rootfs/etc/init.d/S61atomcam) の chroot 起動分岐と、対応する `*_init.sh` を用意（起動バイナリ名・ドライバ引数を機種に合わせる、[03](./03-boot-sequence.md) Stage 5-6）。
3. **libcallback 分岐**: 映像 ch 構成・音声レート・curl URL・SessionHandle 構造体オフセット等を、`wyze`/`swing` に倣った新フラグで分岐（[04](./04-libcallback-injection.md)）。
4. **設定**: 機種固有の設定があれば `hack.ini` にキーを足す（[06. 設定管理](./06-configuration.md) の追加チェックリスト）。
5. **UI**: 機種限定のタブ・項目は `Setting.vue` で `PRODUCT_MODEL` を見て表示制御（カメラ設定タブが ATOM 系のみ、クルーズタブが Swing のみ、等）。

---

## 戻る

- [docs トップ（索引）](./README.md)
