# 主题资源预留目录

四套内置配色现在由 `ui/theme/ui_theme_presets.gd` 代码生成，改起来最方便。
如果想把某套配色做成可复用资源，在 Godot 编辑器里：

1. 新建 `UITheme` 资源；
2. 从 `UIThemePresets.get_theme("ember")` 拷字段，或直接改 Inspector；
3. 保存成 `res://ui/themes/my_theme.tres`；
4. 赋给 `UIRoot.theme_data`（或代码 `ui.apply_theme(load("res://ui/themes/my_theme.tres"))`）。

`.tres` 里包含的是普通 Resource 字段，不依赖运行时。
