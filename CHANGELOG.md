# История изменений

## 1.5.9+ningzh1 — withdraw global regression, QQ-only native-owned visuals

- Restore all non-QQ runtime paths to 1.5.7; keep the shared configuration fix and original Clock reuse/replay logic. Remove the 1.5.8 global hit-test/hosting/input changes.
- Only `com.tencent.mqq` uses the passive visual adapter: the native UISwitch owns touch handling, accessibility, value changes and target/actions. No synthetic value inversion or event forwarding is performed.
- QQ glass is owned by its source switch and validated against parent/cell/list/path. Reuse, hidden/disabled state and another owner invalidate pending visual callbacks.
- QQ capture uses the real row over an opaque ancestor/system background, rather than the transparent switch-only track. Shader, renderer, material and motion constants remain unchanged.
- Fixed SHA256 baseline assertions and extracted production Foundation/QuartzCore/Swift stand-ins are included. Real QQ rendering and touch behavior still require device validation; no claim of an observed device fix.

## 1.5.8+ningzh1 — WITHDRAWN after user-confirmed visual regression

The global source-hosted scheme below failed real-device feedback and is not retained by 1.5.9.

- Non-Clock replacements now live inside their native UISwitch instead of a sibling used by host layout. Native alpha is retained; native drawing layers are masked and conditionally restored on detach.
- Pressed glass samples its own track and stays inside that switch. Gestures bind to source/parent/cell/list/path and cannot commit or restart release after reuse, host rejection, hiding or detachment.
- Added a UISwitch-only hit-test adapter with exact CGPoint ABI validation. Clock reuse/replay and application/notification animations retain their existing paths.
- Regression checks execute extracted production binding/mask/geometry and Swift finishPress/identity code on macOS stand-ins. Visible behavior still requires real-device testing.

## 1.5.7+ningzh1 — integrated liquid switch configuration fix

- Settings and SpringBoard publish the existing saved `LiquidSwitchEnabled` value to one shared snapshot; sandboxed apps no longer query a foreign preference domain.
- Read access is limited to the switch snapshot through a packaged libSandy profile. Missing or malformed updates preserve the last valid state; startup/foreground recovery and metadata diagnostics are included.
- Clock hooks, reuse handling, switch geometry, rendering and animation sources are retained. Tests cover the production snapshot/apply code and independent producer/consumer processes on macOS; real-device rendering still requires installation testing.

## 1.5.5 / Reborn 1.0.0 Beta 2

- fixed crash on ios 15
- fixed notification center cleanup on ios 15
- tested on iphone 13 pro max ios 15.0.2

## 1.5.4

- Иконка при закрытии садится точно на место иконки SnowBoard и больше не дёргается, когда её подменяет иконка рабочего стола.
- Летящая иконка больше не мыльная: при масштабе SnowBoard она рисуется в своём настоящем размере.
- При открытии иконка гнётся вместе с окном и не обрезается квадратом.
- Отскок при свайпе домой задаётся каждому закрытию напрямую и не зависит от состояния настроек SpringBoard.

## 1.5.3

- Крупные иконки (масштаб SnowBoard, темы) больше не обрезаются квадратом при закрытии и гнутся вместе с окном.
- Отскок при свайпе домой больше не пропадает до респринга.
- Новые настройки на английском и русском: на главной включение, скорость, шторка; остальное в «Дополнительно».
- После установки твик выключен, включается в Настройках.

## 1.5.2 — 2026-11-07

- При изменённом масштабе иконок SnowBoard сетка джина не накладывается на слой с иконкой.

## 1.5.1 — 2026-11-07

- Настройки: скорость открытия и закрытия, сила джина и разлёта иконок, «капля», отскок при свайпе,
  прозрачная шторка, размытие при разлёте, замедление твика и всех анимаций, сброс, респринг.
- Исправлены быстрые повторные переходы, запуск джина и восстановление иконок после анимации шторки.

## 1.5.0 — 2026-10-28

- Страница в Настройках «iOS 27 Animations» (нужен PreferenceLoader).
- Отдельные переключатели: «Открытие и закрытие» (`AppAnimations`), «Эффект джина» (`Genie`),
  «Анимация шторки» (`IconFlyIn`). Общий выключатель `Enabled` остался.
- Настройки применяются без респринга (уведомление `com.ning.ios2627anims/changed`).

## 1.4.7 — 2026-10-10

- Пакет переименован в «iOS 27 Animations».

## 1.4.6 Beta 1 — 2026-10-07

- Минимальная версия iOS снижена с 16.0 до 15.0.
