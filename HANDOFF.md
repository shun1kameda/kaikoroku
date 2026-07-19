# コタオデッセイ 開発引き継ぎメモ（Claude Code用）

このプロジェクトは、Godot 4 で作っている3Dアクションゲーム「コタオデッセイ」です。
チャット版のClaudeからClaude Codeへ引き継ぐための状況メモです。まずこれを読んでください。

## ゲームの概要
- スーパーマリオオデッセイの「操作の気持ちよさ」と「箱庭レベルデザインの考え方」を参考にした、完全オリジナルの3Dアクション。
- 見た目・キャラ・世界・素材はすべてオリジナル（任天堂の素材・キャラ・名称は一切使わない方針）。
- 主人公「コタ」（作者の息子がモデル）。目印は青いキャップに黄色い星マーク。
- 収集アイテム「コタムーン」（黄色い月に顔）。集めると新エリアが開く。
- 帽子アクション「チェイス」（青い帽子）＝オデッセイの帽子の"仕組み"を参考にしたオリジナル。未実装。
- 詳しい設計は game_design_document_template.md 参照。

## 技術構成
- エンジン：Godot 4（GDScript）。書き出しは将来HTML5想定。
- 主なファイル：
  - main.tscn … メインシーン（Player / Floor / DirectionalLight3D）
  - player.gd … コタの操作スクリプト（CharacterBody3D にアタッチ）
- ノード構成：
  - Main (Node3D)
    - Player (CharacterBody3D) ← player.gd
      - CollisionShape3D (CapsuleShape3D, radius 0.5 / height 2.0)
      - MeshInstance3D (CapsuleMesh, 青マテリアル)
      - CameraPivot (Node3D)
        - SpringArm3D (spring_length 4)
          - Camera3D
    - Floor (StaticBody3D)
      - MeshInstance3D (BoxMesh 40x1x40)
      - CollisionShape3D (BoxShape3D 40x1x40)
    - DirectionalLight3D (影ON)
- 入力マップ（設定済み）：
  - move_forward=↑,W / move_back=↓,S / move_left=←,A / move_right=→,D
  - jump=Space / dash=Shift（押しっぱなし）

## 完成している機能（Phase 1）
- カメラ相対の移動、ダッシュ、重力、ジャンプ、追従カメラ（マウスで回転）。
- コヨーテタイム・ジャンプ先行入力あり。
- 「見た目のカプセル(mesh)だけを進行方向へ向ける」ことでカメラ追従の回転バグを回避済み。

## 【解決済み】2段・3段ジャンプが段が上がらない問題
- 症状：2段目すら出ない。「跳んだ時の受付残り」がマイナスになり、combo_time を
  1.0 に上げても「受付時間切れ」になっていた。
- **原因（特定済み）**：`was_on_floor` を `move_and_slide()` の**後**（フレーム末）で
  記録していた。Godot の `is_on_floor()` は「最後の move_and_slide の結果」を返すので、
  次フレーム冒頭では `is_on_floor()` と `was_on_floor` が**必ず同じ値**になり、
  着地の立ち上がり `is_on_floor() and not was_on_floor` が
  2フレーム目以降ずっと成立しなかった。→ 着地でコンボ受付（combo_timer）が
  **二度と開かない**ため、2段目が絶対に出なかった（受付残りは常にマイナス）。
- **直し方**：
  1. `was_on_floor = is_on_floor()` を `_physics_process` の**先頭**（move_and_slide の前）
     で記録する（＝1フレーム前の接地状態）。
  2. 着地判定（コンボ受付を開く処理）を `move_and_slide()` の**後**に移動する。
  これで「前フレーム(空中) → 今フレーム(接地)」の立ち上がりが正しく取れる。
- **検証**：フレーム単位のシミュレーション（Godot4 の frame ordering を再現）で確認。
  直す前＝最大1段どまり。直した後＝1段→2段(vy 10.4)→3段(vy 12.8＋宙返り)まで到達。
  実機でも `debug_jump = true` のときログに「★ジャンプ！段=2 / 段=3」が出る。
- 望む挙動（作者の言葉そのまま）：
  「走りながら1段ジャンプ、着地後に2段ジャンプ（1段より高い）、
  　着地後に3段ジャンプ（2段より高い＋宙返り）」→ 実装＆修正済み。

## 現在の player.gd の要点
- 段アップ条件は現在「combo_timer > 0 かつ jump_phase が1〜2」。速さ条件は外し済み。
- @export の主な値：walk_speed 5 / dash_speed 8 / jump_velocity 8 / gravity 20 /
  jump2_mult 1.3 / jump3_mult 1.6 / combo_time 0.6 / flip_time 0.5 /
  coyote_time 0.1 / jump_buffer_time 0.15
- ※インスペクター側で combo_time や jump2/3_mult を上書きしている場合があるので、
  実機の実際の値も確認すること。

## 次のロードマップ（この順で）
1. ~~★2段・3段ジャンプを正しく動かす（最優先）~~ → **完了**（上の【解決済み】参照）
2. ヒップドロップ（空中でCtrlでストンと落ちる）
3. ダイブ（左クリックで前に飛び込む）
4. 帽子「チェイス」投げ（看板アクション）
5. コタムーンの配置と収集（Phase 3）
6. 小さな箱庭ステージ「危険な国」（荒廃した街／列車／バス停）

## 作業の心得
- 動く状態になったら、その都度プロジェクトをバックアップ（コピー）しておくと安全。
- 変更したらこまめに実機（F6）で確認。
