# listen. for qBittorrent

Original cream/sage and forest desktop themes, released under the project MIT license. These style the Qt desktop interface, not the Web UI. Rounded panels and soft colors complement listen.; native macOS window chrome remains native and QSS cannot provide real Liquid Glass blur.

Select `listen-light.qbtheme` or `listen-dark.qbtheme` in qBittorrent → Preferences → Behavior → Use custom UI theme, then restart qBittorrent. Switching light/dark is manual. Disable that checkbox to restore the original theme. No network or proxy settings are changed.

Build with Qt 6: `rcc --binary light/resources.qrc -o listen-light.qbtheme` (and likewise for dark). Editable sources are included. See [official theme documentation](https://github.com/qbittorrent/qBittorrent/wiki/Create-custom-themes-for-qBittorrent).
