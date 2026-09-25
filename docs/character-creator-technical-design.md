# Character Creator: пересмотренный технический дизайн

## Продуктовая гипотеза

Facet не должен начинаться как Character Authoring Platform. Основной пользовательский путь должен требовать минимальных усилий:

```text
Description → Spec → Target Compiler → Chat
                                      ↓
                              Out of Character
                                      ↓
                         Patch → New Version
                                      ↓
                            Regression Case
```

Пользователь описывает человека несколькими предложениями, через несколько секунд начинает разговор и исправляет характер непосредственно через наблюдаемое поведение.

Интервью, Advanced editor и пользовательский Character Lab могут появиться позднее. Они не входят в MVP и должны строиться на данных о реальных OOC-исправлениях, а не на заранее придуманной анкете.

## Основные принципы

1. Источник истины — структурированный, независимый от модели `CharacterSpec`.
2. Prompt — неизменяемый скомпилированный артефакт для конкретного `TargetProfile`.
3. Каждая генерация ссылается на точные версии spec и target-компиляции.
4. Модель предлагает изменения, но сервер валидирует их, а пользователь подтверждает.
5. Психологические противоречия не считаются ошибками; несовместимые поведенческие правила считаются.
6. Проверки безопасности применяются ко всем путям изменения spec.
7. Автоматические тесты персонажей сначала являются внутренним QA-инструментом.
8. Старые версии, prompt snapshots и результаты прогонов никогда не переписываются.

## 1. CharacterSpec

`CharacterSpec` описывает персонажа независимо от Mistral, OpenAI, Claude и конкретного формата system prompt.

В `personality_versions` следует добавить:

```ruby
t.jsonb :spec, null: false, default: {}
t.integer :spec_schema_version, null: false, default: 1
t.string :creation_method, null: false
```

Существующее поле `content` временно сохраняется для совместимости и миграции. Новые генерации должны постепенно перейти на отдельные target-компиляции.

Пример spec:

```json
{
  "identity": {
    "name": "Вера",
    "age": 31,
    "is_adult": true,
    "fictionality": "fictional",
    "appearance": ["рыжая", "выглядит немного потрёпанной"]
  },
  "worldview": {
    "values": ["самостоятельность", "умение не драматизировать"],
    "fears": ["оказаться зависимой от кого-то"],
    "desires": ["близость без потери свободы"]
  },
  "traits": [
    {
      "id": "trait_sexual_openness",
      "label": "сексуально раскрепощённая",
      "interpretation": "считает секс обычной частью жизни",
      "not": ["бравада", "способ добиться внимания"]
    }
  ],
  "tensions": [
    {
      "id": "tension_intimacy_dependency",
      "between": ["desire_for_intimacy", "fear_of_dependency"],
      "expression": "тянется к близости, но отстраняется, когда чувствует зависимость"
    }
  ],
  "voice": {
    "register": "разговорный",
    "vocabulary": ["простые слова", "умеренный мат"],
    "avoid": ["терапевтические формулировки", "тон AI assistant"]
  },
  "behavior_rules": [
    {
      "id": "rule_emotional_problems",
      "when": "собеседник драматизирует свои чувства",
      "does": [
        "сначала реагирует живо и по-человечески",
        "использует поддразнивание и прямой юмор"
      ],
      "avoids": [
        "предлагать спокойно проанализировать чувства",
        "говорить как психолог"
      ],
      "priority": "high",
      "source": "initial_description"
    }
  ],
  "boundaries": [],
  "unknowns": ["как реагирует на ревность"]
}
```

Следует различать:

- факты;
- интерпретации черт;
- психологические tensions;
- наблюдаемые поведенческие правила;
- антипримеры и запрещённые паттерны;
- неизвестные характеристики;
- происхождение каждого существенного правила.

`tensions` — first-class часть персонажа, а не ошибка валидации. Сочетания вроде «хочет близости и боится зависимости» делают поведение живым.

### Создание из свободного описания

MVP начинается с одного поля:

> Опишите человека, с которым хотите разговаривать.

Сервис:

```ruby
CharacterDesign::CreateFromDescription.call(
  user:,
  description:,
  target_profile:
)
```

Utility model преобразует описание в candidate spec. Затем сервер последовательно выполняет:

```text
LLM structured output
        ↓
schema validation
        ↓
domain operation validation
        ↓
safety validation
        ↓
rule conflict validation
        ↓
persist immutable version
        ↓
compile for target
```

Никакого обязательного интервью между описанием и первым разговором нет.

## 2. Target-aware compilation

Один и тот же персонаж требует разного представления для разных моделей. Поэтому компилятор принимает не просто версию шаблона, а target profile:

```ruby
Personalities::CompileCharacter.call(
  spec:,
  target_profile:,
  compiler_version:
)
```

Примеры идентификаторов:

```text
mistral-large-2512/persona-v2
gpt-5.6/persona-v1
claude-sonnet/persona-v1
```

`TargetProfile` задаёт:

- provider и семейство моделей;
- структуру system/developer context;
- набор специальных инструкций и prohibitions;
- few-shot примеры;
- рекомендуемые sampling parameters;
- допустимые provider-specific возможности;
- версию самой стратегии.

Компиляция должна быть детерминированной относительно:

```text
(spec, spec_schema_version, target_profile, compiler_version)
```

### Хранение compiled artifacts

Нельзя добавлять отдельное поле prompt для каждой модели. Нужна отдельная таблица неизменяемых артефактов:

```text
personality_compilations
- personality_version_id
- target_profile_key
- compiler_version
- content
- sampling_parameters        jsonb
- content_checksum
- created_at
```

Уникальный ключ:

```text
(personality_version_id, target_profile_key, compiler_version)
```

Компиляция может быть ленивой: при первом использовании target создаётся и затем переиспользуется неизменяемый snapshot.

`generation_runs` должен получить `personality_compilation_id`. Это позволит точно ответить:

- какой spec использовался;
- для какой модели он был скомпилирован;
- какой prompt реально ушёл провайдеру;
- какие sampling parameters применялись.

Текущий `Ai::PromptBuilder` должен получать compilation artifact, а не читать `personality_version.content` напрямую.

## 3. Out of Character как основной механизм авторинга

У сообщения ассистента появляется действие `Out of character`.

```text
character_feedbacks
- personality_id
- personality_version_id
- personality_compilation_id
- message_id
- user_id
- selected_text
- explanation
- status                    proposed / applied / dismissed
- analysis                  jsonb
- proposed_operations       jsonb
- applied_version_id
- created_at
```

В анализ передаются:

- spec версии, породившей ответ;
- target compilation;
- контекст перед ответом;
- полный ответ и выделенный фрагмент;
- объяснение пользователя.

Модель возвращает не новый spec целиком, а предложение ограниченных domain operations:

```json
{
  "diagnosis": "Персонаж перешёл на терапевтическую манеру речи",
  "affected_rule_ids": ["rule_emotional_problems"],
  "operations": [
    {
      "type": "replace_behavior_rule",
      "rule_id": "rule_emotional_problems",
      "expected_revision": 3,
      "value": {
        "when": "собеседник приносит эмоциональную проблему",
        "does": ["реагирует через знакомое поддразнивание и прямой юмор"],
        "avoids": ["терапевтический framing", "формальные советы"]
      }
    }
  ],
  "possible_side_effects": [
    "может стать слишком резкой в действительно тяжёлых ситуациях"
  ]
}
```

Пользователь видит человеческий diff и только затем нажимает `Apply to character`.

Применение выполняется так:

```text
proposed operations
        ↓
schema validation
        ↓
domain operation validation
        ↓
safety validation
        ↓
rule conflict validation
        ↓
new immutable PersonalityVersion
        ↓
compile for active target
        ↓
create regression case
```

LLM не записывает JSON напрямую и не меняет персонажа без подтверждения.

### Regression case из OOC

Каждое принятое исправление создаёт внутренний regression case:

```text
character_regression_cases
- personality_id
- source_feedback_id
- source_version_id
- expected_rule_ids
- conversation_context
- triggering_message
- rejected_response
- expected_behavior
- forbidden_behavior
- status
```

Так тестовый набор возникает из реальных сбоев, а не из предположений команды.

## 4. Rule conflict detection

Нельзя пытаться «исправлять» противоречивые черты, желания или ценности.

Проверять следует только правила, которые:

1. применяются к одной и той же или явно пересекающейся ситуации;
2. имеют несовместимые обязательные действия;
3. не содержат условий, объясняющих различие.

Например:

```text
WHEN partner becomes jealous
→ patiently reassures them

WHEN partner becomes jealous
→ refuses to reassure them and leaves
```

Это конфликт, если spec не объясняет, когда действует каждый вариант.

Результат detector должен быть одним из:

- `no_conflict`;
- `conditional_tension` — допустимо, можно проверить тестом;
- `ambiguous_rule_conflict` — нужно уточнение перед применением patch;
- `hard_rule_conflict` — patch отклоняется.

Психологические tensions можно использовать при генерации внутренних сценариев, но не показывать пользователю как дефекты персонажа.

## 5. Safety validation

Safety должна быть общей доменной границей, а не частью одного UI-потока.

```ruby
CharacterSafety::ValidateSpec.call(
  spec:,
  source:,
  user:
)
```

Validator вызывается при:

- создании из свободного описания;
- применении OOC correction;
- будущем Advanced editing;
- импорте персонажа;
- будущем conversational interview;
- изменениях, полученных из изображений или других вложений.

Первый набор проверок должен зарезервировать место как минимум для:

- возраста и неоднозначного несовершеннолетия;
- сексуализированного контекста с несовершеннолетними;
- персонажей, явно основанных на реальном человеке;
- использования имени, биографии и likeness публичного или частного лица;
- загружаемых фотографий и иных референсов;
- запрещённых сочетаний характеристик и requested behavior.

Точная продуктовая policy должна быть оформлена отдельно. Архитектурно важно, чтобы все entry points проходили один и тот же validator и не могли обойти его прямой записью spec.

Результат проверки должен быть структурированным:

```json
{
  "status": "allow | reject | needs_clarification | needs_review",
  "violations": [],
  "required_changes": []
}
```

## 6. Внутреннее тестирование персонажей

`Test Character` не входит в пользовательский MVP. Это внутренняя QA-система для разработки target profiles, проверки golden characters и запуска regressions.

Сущности:

```text
character_test_suites
- personality_id
- personality_version_id
- target_profile_key
- compiler_version
- status
- configuration
- summary

character_test_cases
- suite_id
- scenario_key
- scenario
- expected_behavior
- forbidden_behavior
- relevant_rule_ids

character_test_runs
- test_case_id
- personality_compilation_id
- generator_provider
- generator_model
- evaluator_provider
- evaluator_model
- status
- transcript
- observation
- evidence
- verdict
- confidence
- model_metadata
```

`target_profile_key` и точная compilation обязательны: результаты разных моделей и prompt strategies нельзя смешивать в одной агрегации.

Первыми golden characters могут стать уже проработанные Сибилла, Вера и другие внутренние персонажи.

### Калибровка evaluator

До доверия к автоматическим выводам нужен размеченный людьми golden dataset:

```text
human-labelled responses
          ↓
 evaluator candidate A
 evaluator candidate B
          ↓
precision / recall по каждому violation type
```

Особенно важна precision. False positive создаёт уверенное, но ложное утверждение, что персонаж нарушил свой характер.

Требования:

- evaluator по возможности должен быть другой моделью или другим семейством, чем generator;
- каждый verdict обязан содержать evidence;
- метрики считаются отдельно для assistant voice, invented facts, voice drift, boundary violations и других классов;
- пороги применения определяются по golden dataset;
- версия evaluator prompt и модель сохраняются в каждом run;
- до калибровки результаты не показываются пользователям как факты;
- детерминированные проверки используются там, где они возможны;
- OOC regressions запускаются только для затронутых правил и target profiles.

Позже QA-инструмент можно открыть power users как `Character Lab`, но это отдельная продуктовая гипотеза.

## 7. Изменения AI-инфраструктуры

Текущий `Ai::Gateway` поддерживает обычный текстовый ответ. Для initial spec, OOC analysis и evaluator нужен расширенный контракт:

```ruby
gateway.response(
  model:,
  input:,
  response_schema: CharacterDesign::CandidateSpecSchema,
  temperature: 0.2,
  max_output_tokens:
)
```

Понадобятся:

- JSON Schema / structured output;
- строгая локальная валидация ответа;
- один контролируемый repair при невалидном JSON;
- temperature, max output tokens и при наличии seed;
- сохранение фактических параметров запроса;
- новые `ModelCall#purpose`:
  - `character_spec_extraction`;
  - `character_feedback`;
  - `character_simulation`;
  - `character_evaluation`.

Детерминированный target compiler не требует model call и не должен иметь purpose `character_compilation`.

Фоновые regressions используют отдельную очередь `evaluation`, чтобы не задерживать пользовательский чат. Создание initial spec и OOC proposal должно укладываться в короткий интерактивный поток, но также иметь устойчивое фоновое выполнение при необходимости.

## 8. Эволюция схемы spec

`spec_schema_version` неизбежно будет меняться. Старые immutable версии нельзя переписывать массовой миграцией.

Правило:

1. Версия хранит исходный spec в той schema version, в которой была создана.
2. Для чтения и редактирования применяется последовательность чистых upcaster'ов:

   ```ruby
   CharacterSpec::Upcast.call(spec:, from:, to:)
   ```

3. Upcast в памяти не изменяет старую запись.
4. Следующее пользовательское изменение создаёт новую `PersonalityVersion` уже в актуальной schema version.
5. Старые target-компиляции продолжают ссылаться на исходный spec и compiler.
6. Несовместимые старые compiler versions сохраняются минимум столько, сколько требуется для воспроизводимости истории.

Нужно иметь fixtures для каждой schema version и контрактные тесты цепочки upcast.

## 9. Владение и экспорт

До публичного запуска нужно явно закрепить:

- пользователь владеет созданным им персонажем и исходными описаниями;
- пользователь может экспортировать target-independent CharacterSpec;
- экспорт содержит `spec_schema_version` и понятное Markdown-представление;
- поведенческие правила и OOC-исправления входят в экспорт;
- compiled prompt может экспортироваться как диагностический snapshot, но target templates и внутренние compiler assets не обязаны становиться частью переносимого формата;
- удаление персонажа охватывает spec, feedback и приватные transcripts в соответствии с общей retention policy;
- импорт проходит schema, domain и safety validation.

Переносимый контракт — CharacterSpec, а не provider-specific prompt.

## 10. Миграция существующих персонажей

Миграция должна быть консервативной:

1. Для существующей версии `content` создаётся spec с `creation_method: legacy_import`.
2. Исходный Markdown сохраняется как `legacy_notes` или эквивалентная секция без попытки автоматически объявить все выводы достоверными фактами.
3. Для активной модели создаётся `personality_compilation`, содержащая точный прежний `content`.
4. Старые сообщения и generation runs остаются привязаны к прежним версиям.
5. Новые изменения создают нормализованный spec новой schema version.

Нельзя заново скомпилировать старый Markdown и утверждать, что новый prompt идентичен историческому.

## 11. Границы MVP

### Входит

- одно свободное описание персонажа;
- structured extraction в CharacterSpec;
- schema, domain, safety и rule-conflict validation;
- target-aware compiler;
- immutable compilation snapshots;
- немедленный переход в чат;
- `Out of character`;
- preview и подтверждение patch;
- новая immutable version;
- regression case из принятой правки;
- внутренний запуск regressions;
- миграция существующих персонажей;
- базовый export CharacterSpec.

### Не входит

- обязательное designer interview;
- adaptive questions;
- Advanced editor;
- публичный Test Character;
- пользовательские оценки качества вида «13 из 15»;
- автономные многотуровые симуляции;
- автоматическое «исправление» психологических противоречий;
- большой универсальный character-authoring UI.

## 12. Порядок реализации

### Шаг 1. Версионируемый spec и target compilation

- определить JSON Schema v1;
- добавить `spec` и `spec_schema_version`;
- определить registry `TargetProfile`;
- добавить `personality_compilations`;
- связать generation run с compilation;
- перевести `Ai::PromptBuilder` на compiled artifact;
- мигрировать существующие версии без потери исторического prompt.

### Шаг 2. Description → Spec → Chat

- заменить многошаговую форму одним свободным описанием;
- добавить structured extraction;
- провести candidate spec через все validators;
- скомпилировать для активного target;
- сразу открыть первый разговор.

Это первый момент, когда гипотезу можно показывать незнакомым пользователям.

### Шаг 3. OOC → Patch → New Version

- добавить feedback action к сообщению;
- реализовать анализ и ограниченные domain operations;
- показать понятный preview;
- после подтверждения создать новую версию и compilation;
- автоматически создать regression case.

Это главный «магический» цикл продукта.

### Шаг 4. Внутренние regressions

- собрать кейсы из OOC;
- добавить несколько golden characters;
- создать вручную размеченный evaluator dataset;
- измерить precision/recall;
- запускать selective regressions по rules и targets;
- использовать результаты для улучшения target profiles.

### Только после появления данных

По статистике реальных OOC corrections можно решить:

- какие вопросы стоит добавить в optional interview;
- какие поля нужны Advanced editor;
- нужен ли пользователям Character Lab;
- какие части spec систематически не извлекаются из свободного описания.

## Критерий успешности

Первая версия должна доказать только один сценарий:

> Незнакомый человек пишет несколько предложений, быстро получает персонажа, проводит хороший разговор, один раз говорит «нет, она так не говорит» и видит, что Facet правильно понял исправление в следующих ответах.

Если этот цикл не создаёт ценности, глубокая authoring platform не нужна. Если создаёт — реальные OOC-данные подскажут, что строить дальше.
