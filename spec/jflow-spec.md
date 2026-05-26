# jflow — техническое задание

## 1. Описание

**jflow** — система управления многоэтапными задачами в Claude Code, организованная как набор skills, hooks и вспомогательных скриптов. Цель — минимизировать расход контекста, обеспечить надёжное возобновление работы после очистки контекста и предотвратить неконтролируемый auto-compact.

### Принципы

1. **Этапная декомпозиция.** Каждая задача проходит фиксированную последовательность этапов: `spec → design → plan → impl → test → release`. Каждый этап живёт в своём markdown-файле и имеет явные входы/выходы.
2. **Минимизация контекста.** В контекст этапа подгружаются только релевантные ему файлы (текущий этап + предыдущие как краткие резюме + объявленные зависимости).
3. **Гибридное сохранение состояния.** Состояние пишется двумя путями: автоматический дамп из transcript (надёжно, но сырьё) + осмысленное резюме Claude'ом по явному вызову (содержательно). Оба варианта используются вместе.
4. **Project-scope.** Вся конфигурация и состояние живут в `.claude/` внутри проекта. Универсальная работа через `$CLAUDE_PROJECT_DIR` без хардкода путей.
5. **Opt-in поведение.** Skills не активируются автоматически. Все команды требуют явного вызова пользователем.
6. **Лёгкие hooks.** Hooks делают минимум работы. Тяжёлые операции — только в skills, вызываемых явно.

### Что система НЕ делает

- Не создаёт subagents динамически.
- Не использует встроенный `/clear` напрямую (заменяется на `/jclear`).
- Не пишет state на каждый Stop hook (только мониторинг порога).
- Не лезет в git автоматически (только в команде `/jrelease` при явном вызове).

---

## 2. Структура

### Дерево файлов

```
$CLAUDE_PROJECT_DIR/
└── .claude/
    ├── settings.json                    # hooks конфигурация
    ├── current-task                     # однострочник: ID активной задачи
    ├── scripts/
    │   ├── statusline.sh                # обновление statusline + bridge
    │   ├── stop-monitor.sh              # лёгкий мониторинг порога (Stop hook)
    │   ├── session-end-snapshot.sh      # автодамп при выходе (SessionEnd hook)
    │   └── session-start-restore.sh     # подгрузка state при старте (SessionStart hook)
    ├── skills/
    │   ├── jnew/SKILL.md                # создание новой задачи
    │   ├── jstage/SKILL.md              # переключение этапа
    │   ├── jstep/SKILL.md               # фиксация шага внутри этапа
    │   ├── jphase/SKILL.md              # отчёт о текущем этапе
    │   ├── jstatus/SKILL.md             # обзор всех задач
    │   ├── jhandoff/SKILL.md            # явное резюме сессии
    │   ├── jclear/SKILL.md              # checkpoint + clear
    │   ├── jdeps/SKILL.md               # управление зависимостями между задачами
    │   └── _templates/                  # шаблоны этапов
    │       ├── 00-spec.md
    │       ├── 01-design.md
    │       ├── 02-plan.md
    │       ├── 03-impl.md
    │       ├── 04-test.md
    │       ├── 05-release.md
    │       └── state.md
    └── tasks/
        └── <task-id>/                   # одна задача = одна директория
            ├── 00-spec.md
            ├── 01-design.md
            ├── 02-plan.md               # обновляемый план
            ├── 03-impl.md
            ├── 04-test.md
            ├── 05-release.md
            ├── state.md                 # текущее состояние задачи
            ├── deps.md                  # зависимости от других задач
            └── events.jsonl             # лог событий (дешёвый, fast path)
```

### Bridge-файл

Statusline и hooks обмениваются информацией о контексте через файл:

```
/tmp/jflow-ctx-<hash>.json
```

где `<hash>` — короткий хэш от `$CLAUDE_PROJECT_DIR` (например, `sha256sum | head -c 8`). Это обеспечивает изоляцию между параллельными сессиями в разных проектах.

Формат файла:
```json
{
  "context_percent": 42,
  "total_input_tokens": 85000,
  "total_output_tokens": 3200,
  "updated_at": "2026-05-26T14:30:00Z"
}
```

### Конвенции именования

- Task ID: kebab-case, опционально с namespace через `/`. Примеры: `funding-arb-v2`, `trading/clickhouse-migration`.
- Этапы пронумерованы (`00-spec.md`, `01-design.md`, …) для естественной сортировки.
- Все команды skills начинаются с `j` (jflow).

---

## 3. Skills

Все skills хранятся в `.claude/skills/<name>/SKILL.md`. Каждый файл имеет frontmatter с `description` для самодокументирования и `disable-model-invocation: true` — чтобы skills не активировались автоматически. Дополнительно у скиллов, требующих явного управления токенами, может быть `allowed-tools`.

### 3.1 `/jnew` — создание новой задачи

**Назначение.** Создаёт скелет директории `.claude/tasks/<task-id>/` со всеми этапами из шаблонов.

**Аргументы.** `<task-id>` — обязательный. Опционально `--from <task-id>` для копирования зависимостей из другой задачи.

**Алгоритм:**
1. Если директория `.claude/tasks/<task-id>/` уже существует — отказ с сообщением.
2. Создать директорию.
3. Скопировать все файлы из `.claude/skills/_templates/` в задачу.
4. В `00-spec.md` подставить заголовок задачи и текущую дату.
5. Записать `<task-id>` в `.claude/current-task`.
6. Создать пустой `events.jsonl`.
7. Вывести путь к `00-spec.md` с просьбой к пользователю заполнить.

**Acceptance criteria:**
- Идемпотентность: повторный вызов с тем же ID не перезаписывает существующие файлы.
- Все 6 этапов созданы.
- Текущая задача установлена.

### 3.2 `/jstage` — переключение этапа

**Назначение.** Переключает фокус работы на указанный этап текущей задачи и подгружает в контекст только релевантные файлы.

**Аргументы.** `<stage>` ∈ `{spec, design, plan, impl, test, release}`.

**Алгоритм:**
1. Прочитать `.claude/current-task` → получить task-id.
2. Прочитать `state.md` задачи — получить текущий этап и контекст.
3. Загрузить в контекст:
   - Файл нового этапа целиком.
   - Резюме (последние 30 строк) каждого ранее закрытого этапа.
   - `deps.md` целиком, если не пустой.
4. Обновить в `state.md` поле `current_stage`.
5. Вывести краткое сообщение: «Этап переключён на X. Подгружено: [список]».

**Acceptance criteria:**
- В контекст не попадают этапы, которые ещё не начаты.
- Резюме предыдущих этапов — не более 30 строк каждое.
- state.md обновлён.

### 3.3 `/jstep` — фиксация шага внутри этапа

**Назначение.** Записывает короткую отметку о прогрессе в рамках текущего этапа. Используется во время длинной работы, чтобы не терять промежуточные результаты.

**Аргументы.** `<message>` — описание шага в свободной форме.

**Алгоритм:**
1. Прочитать `.claude/current-task` и `state.md` → определить текущий этап.
2. В соответствующий файл этапа (например, `02-plan.md`) дописать в конце:
   ```
   ### Step <timestamp>
   <message>
   ```
3. Дописать в `events.jsonl`:
   ```json
   {"ts":"...","type":"step","stage":"plan","message":"..."}
   ```

**Acceptance criteria:**
- Запись не нарушает существующую структуру файла этапа.
- events.jsonl остаётся валидным jsonl.

### 3.4 `/jphase` — отчёт о текущем этапе

**Назначение.** Без аргументов — выводит сводку: какая задача активна, какой этап, что сделано, что осталось.

**Алгоритм:**
1. Прочитать `.claude/current-task` и `state.md`.
2. Вывести в чате (без записи в файлы) форматированную сводку из state.md.
3. Если `events.jsonl` существует — добавить «активность за последние 24 часа» (число шагов, tool calls).

**Acceptance criteria:**
- Чистое read-only действие, ничего не модифицирует.
- Вывод компактный (≤ 30 строк).

### 3.5 `/jstatus` — обзор всех задач

**Назначение.** Без аргументов — выводит список всех задач в `.claude/tasks/` с их состоянием.

**Алгоритм:**
1. Перечислить директории в `.claude/tasks/`.
2. Для каждой прочитать `state.md` и извлечь: текущий этап, дату последнего обновления, статус (active/blocked/done).
3. Вывести таблицу.

**Acceptance criteria:**
- Read-only.
- Сортировка по дате последнего обновления, новые сверху.

### 3.6 `/jhandoff` — явное резюме сессии

**Назначение.** Финализирует работу в текущей сессии: Claude осмысленно пишет резюме в `state.md` задачи.

**Алгоритм:**
1. Прочитать `.claude/current-task` → task-id.
2. Прочитать текущий `state.md` задачи.
3. Claude **сам пишет** обновлённый `state.md` со следующими секциями:
   - `Stage`: текущий этап
   - `Last update`: timestamp
   - `Done`: что закрыто (накопительно, обновлять)
   - `In progress`: что в работе сейчас
   - `Open questions`: открытые вопросы
   - `Next`: следующие шаги
   - `Context for resume`: 5-10 строк дистиллята, по которым можно возобновить работу без транскрипта
4. Дописать в `events.jsonl`:
   ```json
   {"ts":"...","type":"handoff","stage":"...","tokens_used":<из bridge>}
   ```
5. Вывести путь к обновлённому state.md.

**Acceptance criteria:**
- Claude пишет state.md **сам**, не скриптом. Это содержательное резюме, не дамп.
- Накопительный режим: предыдущие записи в `Done` сохраняются.
- Секция `Context for resume` — это то, что прочитает SessionStart hook при возобновлении.

### 3.7 `/jclear` — checkpoint + clear

**Назначение.** Безопасная очистка контекста с предварительным сохранением. Заменяет встроенный `/clear`.

**Алгоритм (гибрид):**
1. Прочитать `/tmp/jflow-ctx-<hash>.json` → context_pct.
2. **Если context_pct ≥ 60% ИЛИ задача активна:**
   - Claude выполняет `/jhandoff` (см. 3.6) — пишет осмысленное резюме.
3. **Всегда** запускается `session-end-snapshot.sh` — пишет автодамп из transcript в `state.md` секцию `Auto-snapshot` (отдельно от осмысленных секций, чтобы не затирать).
4. Дописать в `events.jsonl`:
   ```json
   {"ts":"...","type":"clear","context_pct":<n>,"handoff_done":<bool>}
   ```
5. Вывести инструкцию пользователю: «Состояние сохранено. Введите `/clear` для очистки контекста, затем команду продолжения работы».

**Важно:** `/jclear` **не вызывает** встроенный `/clear` напрямую — это сделает пользователь. Skill только готовит почву и инструктирует.

**Acceptance criteria:**
- Если context_pct < 60% И задачи нет — выполняется только автодамп, Claude не пишет резюме.
- Если context_pct ≥ 60% — обязательно Claude пишет осмысленное резюме.
- После выполнения пользователь точно знает следующий шаг.

### 3.8 `/jdeps` — управление зависимостями

**Назначение.** Просмотр и редактирование `deps.md` текущей задачи.

**Аргументы.**
- Без аргументов — показать `deps.md`.
- `add <task-id> [--type depends-on|blocks|related]` — добавить зависимость.
- `remove <task-id>` — удалить.

**Алгоритм:**
1. Прочитать `.claude/current-task`.
2. Открыть/создать `deps.md` в директории задачи.
3. Выполнить операцию.

**Формат deps.md:**
```
depends-on: <task-id> (<optional comment>)
blocks: <task-id>
related: <task-id>
```

**Acceptance criteria:**
- Валидация: указанный task-id должен существовать в `.claude/tasks/`.
- Симметрия: при добавлении `depends-on: X` в задачу A — в задачу X автоматически дописывается `blocks: A`.

---

## 4. Механизм сохранения текущего состояния

### Гибридная модель

Состояние задачи живёт в `state.md` и наполняется **двумя путями**, которые не конфликтуют:

**Путь 1: осмысленное резюме (slow path, ручное).**
- Триггер: пользователь явно вызывает `/jhandoff` или `/jclear`.
- Содержание: Claude **сам пишет** разделы `Done`, `In progress`, `Open questions`, `Next`, `Context for resume`.
- Это дистиллят, по которому можно возобновить работу.

**Путь 2: автодамп из transcript (fast path, автоматический).**
- Триггер: SessionEnd hook при выходе из сессии (`/exit`, Ctrl+D, закрытие терминала, встроенный `/clear`).
- Содержание: скрипт парсит `transcript_path`, извлекает метаданные (tool calls в сессии, изменённые файлы, время, токены) и дописывает в секцию `Auto-snapshot` файла `state.md`.
- Это сырьё для аудита, не для возобновления.

### Структура state.md

```markdown
# Task state: <task-id>

**Created:** <iso-date>
**Stage:** <current-stage>
**Last update:** <iso-date>
**Status:** active | blocked | done

## Done
- <закрытые пункты, накопительно>

## In progress
- <что в работе>

## Open questions
- <открытые вопросы>

## Next
- <следующие шаги>

## Context for resume

<5-10 строк дистиллята: ключевые решения, что нужно знать,
чтобы продолжить работу без оригинального transcript>

---

## Auto-snapshot

<автоматически дописывается SessionEnd hook'ом;
содержит метаданные последних N сессий>
```

### Цикл сохранение → возобновление

1. Пользователь работает в сессии.
2. По мере прогресса: `/jstep "сделал X"` — короткие отметки.
3. Перед концом работы: `/jhandoff` — Claude пишет осмысленное резюме.
4. Пользователь делает `/exit` или Ctrl+D → срабатывает SessionEnd hook → автодамп в `Auto-snapshot`.
5. Следующая сессия: SessionStart hook читает `state.md` и инжектит в контекст секцию `Context for resume` + 5 последних строк `In progress` и `Next`.
6. Claude видит state и продолжает работу без переспрашивания.

### Гарантии надёжности

- **Осмысленное резюме** не зависит от hook'ов — Claude пишет файл напрямую. Работает на 100%, если пользователь вызвал команду.
- **Автодамп** работает в 99% случаев — не срабатывает только при `kill -9` или панике CLI.
- **Возобновление** работает на 100%, если хоть один из двух источников записал что-то в `state.md`.

---

## 5. Hooks

Конфигурация в `.claude/settings.json`. Все hooks ссылаются на скрипты через `$CLAUDE_PROJECT_DIR`.

### 5.1 Statusline

**Скрипт:** `.claude/scripts/statusline.sh`

**Назначение:**
1. Обновлять строку статуса в Claude Code (модель, ветка git, % контекста, стоимость).
2. **Главное:** писать `/tmp/jflow-ctx-<hash>.json` для чтения другими hooks.

**Алгоритм:**
1. Читать JSON из stdin.
2. Извлечь `context_window.used_percentage`, `total_input_tokens`, `total_output_tokens`, `model.display_name`, `workspace.current_dir`.
3. Вычислить хэш cwd:
   ```bash
   hash=$(echo -n "$cwd" | shasum | cut -c1-8)
   ```
4. Записать в `/tmp/jflow-ctx-$hash.json`:
   ```json
   {"context_percent": <n>, "total_input_tokens": <n>, "total_output_tokens": <n>, "updated_at": "<iso>"}
   ```
5. Сформировать строку статуса:
   ```
   <model>  |  <branch>  |  ctx:<n>%  |  $<cost>
   ```
6. Если `context_percent ≥ 75` — добавить `⚠️ /jclear`.
7. Если `60 ≤ context_percent < 75` — добавить `🟡 handoff soon`.
8. Вывести строку в stdout.

**Acceptance criteria:**
- Не падает, если stdin пустой или невалидный.
- Bridge-файл всегда консистентен.
- Скрипт выполняется за < 100ms.

### 5.2 Stop hook — лёгкий мониторинг

**Скрипт:** `.claude/scripts/stop-monitor.sh`

**Назначение.** На каждый Stop читать context_pct из bridge и **только при пересечении порога** инжектить предупреждение в контекст Claude.

**Алгоритм:**
1. Дрейнить stdin (содержимое не нужно).
2. Вычислить hash от `$CLAUDE_PROJECT_DIR`.
3. Прочитать `/tmp/jflow-ctx-$hash.json` → context_pct.
4. Прочитать `/tmp/jflow-last-warn-$hash` (если есть) → last_warned_level.
5. Определить current_level:
   - `< 60` → `ok`
   - `60..74` → `warning`
   - `≥ 75` → `critical`
6. Если current_level ≠ last_warned_level И current_level ≠ `ok`:
   - Записать current_level в `/tmp/jflow-last-warn-$hash`.
   - Вывести в stdout сообщение для Claude:
     - `warning`: «Контекст: <n>%. Рекомендую запланировать `/jhandoff` и `/jclear` в ближайшее время».
     - `critical`: «Контекст: <n>%. Критический уровень. Выполни `/jhandoff` сейчас, затем `/jclear`».
7. Иначе — молча выйти.

**Acceptance criteria:**
- Throttle: один раз на пересечение порога, не на каждый Stop.
- Скрипт выполняется за < 50ms.
- Не пишет в state, не дёргает git, не парсит transcript.

### 5.3 SessionEnd hook — автодамп

**Скрипт:** `.claude/scripts/session-end-snapshot.sh`

**Назначение.** При завершении сессии (`/exit`, встроенный `/clear`, Ctrl+D, закрытие терминала) автоматически дописать секцию `Auto-snapshot` в `state.md` текущей задачи.

**Алгоритм:**
1. Читать JSON из stdin.
2. Извлечь `session_id`, `transcript_path`, `cwd`, `reason`.
3. Прочитать `$cwd/.claude/current-task` → task-id. Если нет — выйти.
4. Прочитать `transcript_path`, извлечь:
   - Количество tool_use в сессии (по типам).
   - Список уникальных файлов в Read/Write/Edit.
   - Время старта и конца сессии.
   - Финальные input/output tokens из последнего usage блока.
5. Сформировать блок:
   ```markdown
   ### Session <session-id> ended at <ts> (reason: <reason>)
   - Tools used: Bash×N, Read×N, Write×N, Edit×N
   - Files touched: <list>
   - Duration: <minutes>m
   - Tokens: <in>/<out>
   ```
6. Дописать (append) в секцию `## Auto-snapshot` файла `state.md` задачи. Если секции нет — создать.
7. Дописать в `events.jsonl`:
   ```json
   {"ts":"...","type":"session_end","reason":"<reason>","session":"<id>"}
   ```

**Acceptance criteria:**
- Не модифицирует осмысленные секции state.md (`Done`, `In progress` и т.п.).
- Работает за timeout SessionEnd (по умолчанию обычно несколько секунд).
- Идемпотентность: повторный запуск для той же сессии не дублирует запись.

### 5.4 SessionStart hook — подгрузка state

**Скрипт:** `.claude/scripts/session-start-restore.sh`

**Назначение.** При старте новой сессии инжектить в контекст краткое состояние активной задачи.

**Алгоритм:**
1. Читать JSON из stdin (для получения source: startup/resume/clear).
2. Прочитать `$CLAUDE_PROJECT_DIR/.claude/current-task` → task-id. Если нет — выйти молча.
3. Прочитать `state.md` задачи. Извлечь секции:
   - `Stage`
   - `Status`
   - `In progress` (последние 5 строк)
   - `Next` (последние 5 строк)
   - `Context for resume` целиком
4. Вывести в stdout (этот текст попадёт в контекст Claude):
   ```
   ## Активная задача: <task-id>
   Этап: <stage> | Статус: <status>

   В работе:
   <In progress>

   Следующие шаги:
   <Next>

   Контекст для возобновления:
   <Context for resume>

   Для смены задачи: /jstatus и /jstage.
   ```

**Acceptance criteria:**
- Объём инжектируемого текста ≤ 50 строк.
- Не падает при отсутствии state.md (просто молчит).
- Работает за < 100ms.

### 5.5 Конфигурация settings.json

```json
{
  "statusLine": {
    "type": "command",
    "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/statusline.sh"
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/stop-monitor.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/session-end-snapshot.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/scripts/session-start-restore.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

---

## 6. Механизм очистки контекста с предварительным сохранением (`/jclear`)

### Логика гибрида

`/jclear` — это skill (`.claude/skills/jclear/SKILL.md`), который **не вызывает** встроенный `/clear` за пользователя (это технически невозможно из skill). Вместо этого он готовит состояние и инструктирует пользователя.

### Полный сценарий

```
Пользователь: /jclear
   │
   ▼
[Skill читает /tmp/jflow-ctx-<hash>.json]
   │
   ├─── context_pct < 60% И current-task пуст ────┐
   │                                              │
   ▼ context_pct ≥ 60% ИЛИ current-task есть      │
[Claude выполняет /jhandoff:                      │
 пишет осмысленное резюме в state.md]             │
   │                                              │
   └──────────────────┬───────────────────────────┘
                      │
                      ▼
   [Claude сообщает пользователю:
    "Резюме сохранено. Введите /clear, затем 'Продолжай'."]
                      │
                      ▼
   [Пользователь вводит /clear]
                      │
                      ▼
   [SessionEnd hook срабатывает с reason=clear,
    дописывает Auto-snapshot в state.md]
                      │
                      ▼
   [Стартует новая сессия]
                      │
                      ▼
   [SessionStart hook читает state.md
    и инжектит Context for resume в новый контекст]
                      │
                      ▼
   [Пользователь пишет "Продолжай",
    Claude видит state и работает дальше]
```

### Skill `/jclear` — детальный алгоритм

1. Прочитать `/tmp/jflow-ctx-<hash>.json` → context_pct.
2. Прочитать `$CLAUDE_PROJECT_DIR/.claude/current-task` → task-id (может быть пусто).
3. Определить ветку:
   - **Ветка A**: context_pct < 60% И task-id отсутствует.
     - Сообщить: «Контекст низкий (<n>%), активной задачи нет. Можно делать `/clear` без подготовки».
     - Завершить.
   - **Ветка B**: иначе.
     - Выполнить логику `/jhandoff` (см. 3.6): Claude пишет осмысленное резюме в state.md задачи.
     - Дописать в `events.jsonl` запись типа `jclear`.
     - Сообщить пользователю:
       ```
       ✅ Резюме сохранено в .claude/tasks/<task-id>/state.md
       Контекст: <n>%
       
       Теперь:
       1. Введите /clear для очистки.
       2. Затем напишите "Продолжай" или конкретную задачу.
       
       SessionStart hook автоматически загрузит резюме в новый контекст.
       ```

### Почему именно так, а не «skill вызывает /clear автоматически»

`/clear` — это встроенная команда Claude Code, которая интерпретируется CLI **до** того, как доходит до Claude. Skill, выполняемый Claude'ом, не может вписать `/clear` в свой output и ожидать, что CLI это перехватит. Единственный надёжный способ — пользователь сам вводит `/clear` после того, как skill подготовил состояние.

Альтернатива через `permissions.deny` для встроенного `/clear` — теоретически возможна, но это потребует от пользователя дисциплины использовать только `/jclear`. Не блокируется на уровне ТЗ — оставляется на усмотрение пользователя.

### Acceptance criteria для /jclear

- При context_pct ≥ 60% или активной задаче — гарантированно вызывает `/jhandoff` логику.
- Не пытается технически выполнить `/clear` — только инструктирует.
- Событие `jclear` записано в `events.jsonl`.
- После последующего ввода `/clear` пользователем — SessionEnd hook отрабатывает автодамп, SessionStart hook новой сессии загружает state.

---

## Приложение A: Шаблоны этапов

Шаблоны лежат в `.claude/skills/_templates/`. Минимальное содержимое каждого:

### 00-spec.md
```markdown
# Spec: <task-name>

**Created:** <date>

## Problem

<что решаем, в чём суть>

## Goals

- <цель 1>
- <цель 2>

## Non-goals

- <что НЕ делаем>

## Success criteria

- <как поймём, что готово>
```

### 01-design.md
```markdown
# Design: <task-name>

## Approach

<выбранный подход на верхнем уровне>

## Alternatives considered

- <альтернатива 1>: <почему отвергли>

## Key decisions

- <решение>: <обоснование>

## Open questions

- <вопрос>
```

### 02-plan.md (обновляемый план)
```markdown
# Plan: <task-name>

**Last updated:** <date>

## Milestones

- [ ] <milestone 1>
- [ ] <milestone 2>

## Current focus

<что делаем прямо сейчас>

## Next up

<что следующее>

## Blockers

<что мешает>
```

### 03-impl.md
```markdown
# Implementation: <task-name>

## What was built

<накопительно: что сделано>

## Files changed

<основные затронутые пути>

## Notes for review

<на что обратить внимание>
```

### 04-test.md
```markdown
# Tests: <task-name>

## Test coverage

<что покрыто>

## Manual checks

- [ ] <чек>

## Known issues

<известные проблемы>
```

### 05-release.md
```markdown
# Release: <task-name>

## Checklist

- [ ] Code review
- [ ] Tests passing
- [ ] Documentation updated
- [ ] Migration plan (if needed)

## Rollout

<как раскатываем>

## Rollback

<как откатываем, если что>
```

### state.md
```markdown
# Task state: <task-id>

**Created:** <date>
**Stage:** spec
**Last update:** <date>
**Status:** active

## Done

## In progress

## Open questions

## Next

## Context for resume

---

## Auto-snapshot
```

---

## Приложение B: Формат events.jsonl

Каждая строка — отдельный JSON-объект. Минимальные обязательные поля:

```json
{"ts": "ISO-8601", "type": "<event-type>", "task": "<task-id>"}
```

Типы событий:
- `task_created`: при `/jnew`
- `stage_changed`: при `/jstage` (+ поле `to_stage`)
- `step`: при `/jstep` (+ поле `message`, `stage`)
- `handoff`: при `/jhandoff` (+ поле `stage`, `tokens_used`)
- `jclear`: при `/jclear` (+ поле `context_pct`, `handoff_done`)
- `session_end`: SessionEnd hook (+ поле `reason`, `session`)
- `threshold_crossed`: Stop hook при пересечении порога (+ поле `level`, `context_pct`)

---

## Приложение C: Acceptance criteria всей системы

1. **Чистая инсталляция.** В пустом проекте после копирования `.claude/` всё работает без дополнительных настроек.
2. **Универсальность.** Все скрипты используют `$CLAUDE_PROJECT_DIR`, никаких хардкод-путей.
3. **Изоляция между проектами.** Параллельные сессии в разных проектах не конфликтуют (bridge через hash).
4. **Минимальные требования.** Зависимости: `bash`, `jq`, `git`, стандартные unix-утилиты. Никакого Python/Node.
5. **Производительность.** Statusline и Stop hook отрабатывают за < 100ms каждый. Не должно быть видимых лагов в интерактивной работе.
6. **Отказоустойчивость.** Любой hook при ошибке (отсутствие файла, невалидный JSON) — молча выходит с кодом 0. Не блокирует работу Claude Code.
7. **Идемпотентность.** Все skills можно безопасно повторять; результат тот же.
8. **Обратная совместимость.** Встроенный `/clear` продолжает работать; `/jclear` — это рекомендуемая обёртка, а не замена.

---

## Приложение D: Открытые вопросы для реализации

Эти вопросы оставляю на обсуждение в процессе реализации, не фиксирую в ТЗ жёстко:

1. **Очистка `/tmp` bridge-файлов.** Старые файлы накапливаются. Нужен ли cron/launchd-скрипт для очистки старше N дней?
2. **Архивация закрытых задач.** При статусе `done` — переносить ли в `.claude/tasks/_archive/`?
3. **Multi-task в одной сессии.** Что делать, если пользователь работает над несколькими задачами параллельно? Сейчас `current-task` — однострочник. Возможно, стоит расширить до стека.
4. **Granularity events.jsonl.** Записывать ли каждый tool_use или только high-level события? Сейчас — только high-level.
5. **Интеграция с git.** Привязывать ли task-id к branch name автоматически? Сейчас — нет, оставлено вручную.
