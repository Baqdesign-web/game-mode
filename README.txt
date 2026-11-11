GAME MODE / ИГРОВОЙ РЕЖИМ  (v2)
================================

RU
1. Распакуйте архив в любую папку.
2. Запустите GameMode.exe (в окне Windows нажмите "Да": права администратора нужны, чтобы
   временно остановить лишние службы). Если exe блокируется антивирусом/SmartScreen - запустите
   GameMode.bat (делает то же самое).
3. Появятся окна:
   - "Включить игровой режим?"  Да / Нет
   - "Закрыть все эти программы?"  Да / Нет  (список открытых программ показан в окне)
4. Откроется панель с играми: Steam (вся библиотека, включая нескачанные), Epic Games и
   локальные/торрент-игры. Нажмите на карточку - игра запустится.
   Правый клик по игре - скрыть её. Прокрутка: колесо мыши, полоса справа, PageUp/PageDown.
5. Кнопка "Настройки" (вверху): что спрашивать при запуске, закрывать ли программы, прятать ли панель
   задач и значки, какие источники игр показывать, свои папки с играми, список закрываемых программ.
6. Выход: ТОЛЬКО красная кнопка "Выйти из игрового режима" (Esc не работает).

Значки рабочего стола НЕ удаляются и проводник не перезапускается: значки и панель задач только
прячутся на время игры и сразу возвращаются при выходе. Если что-то осталось скрытым (например,
программу закрыли через диспетчер задач) - запустите "Restore.bat".

Торрент-игры: ищутся автоматически в папках Games / Игры, Downloads и в папках загрузки qBittorrent
(папка игры должна весить от 300 МБ и содержать .exe). Свои папки добавляются в Настройках.

Требования: Windows 10/11 (PowerShell 5.1). На Windows 7 не проверялось.
Антивирус, драйверы и Steam/Epic не затрагиваются. План электропитания возвращается при выходе.
Настройки хранятся в %APPDATA%\GameMode\settings.json.

EN
1. Unzip anywhere.
2. Run GameMode.exe and click "Yes" on the Windows prompt (admin rights are needed to pause a few
   non-essential services). If antivirus/SmartScreen blocks the exe, run GameMode.bat instead.
3. Two prompts: "Turn on game mode?" and "Close all these programs?" (the list is shown).
4. A launcher with your games opens: Steam (whole library incl. not installed), Epic Games and
   local/torrent games. Click a card to launch. Right-click a game to hide it. Scroll with the mouse
   wheel, the bar on the right, or PageUp/PageDown.
5. "Settings" button (top): start-up questions, closing programs, taskbar/icons, game sources,
   your own game folders, programs to close.
6. Exit: ONLY the red "Exit game mode" button (Esc does nothing).

Desktop icons are NOT deleted and Explorer is not restarted: icons and the taskbar are only hidden
and shown again on exit. If something stays hidden (e.g. the program was killed) run "Restore.bat".

Torrent games are found automatically in Games / Игры, Downloads and qBittorrent save folders
(game folder >= 300 MB with an .exe). Add your own folders in Settings.

Needs Windows 10/11 (PowerShell 5.1). Not tested on Windows 7. Settings: %APPDATA%\GameMode\settings.json
