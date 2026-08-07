<p align="center">
  <strong>🔐 vaultwarden-keenetic</strong>
</p>

<p align="center">
  <a href="README.md">🇬🇧 English</a>
</p>

<p align="center">
  <a href="https://github.com/MusubaPy/vaultwarden-keenetic/actions"><img src="https://img.shields.io/github/actions/workflow/status/MusubaPy/vaultwarden-keenetic/build.yml?style=flat&colorA=222222&colorB=3FB950" alt="CI"></a>
  <a href="https://github.com/MusubaPy/vaultwarden-keenetic/releases/latest"><img src="https://img.shields.io/github/v/release/MusubaPy/vaultwarden-keenetic?style=flat&colorA=222222&colorB=58A6FF" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/MusubaPy/vaultwarden-keenetic?style=flat&colorA=222222&colorB=58A6FF" alt="License"></a>
  <a href="https://www.rust-lang.org"><img src="https://img.shields.io/badge/Rust-DEA584?style=flat&colorA=222222&logo=rust&logoColor=white" alt="Rust"></a>
  <a href="https://www.mips.com"><img src="https://img.shields.io/badge/MIPS32r2-003366?style=flat&colorA=222222" alt="MIPS32r2"></a>
  <a href="https://keenetic.com"><img src="https://img.shields.io/badge/Keenetic-00A651?style=flat&colorA=222222&logo=keenetic&logoColor=white" alt="Keenetic"></a>
</p>

<p align="center">
  Запуск <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> на роутере Keenetic с <strong>256 МБ ОЗУ</strong>.
  <br>
  Кросс-компиляция для MIPS32r2 big-endian · Без Docker · Без доп. пакетов.
</p>

---

## Целевое оборудование

| | |
|---|---|
| **Роутер** | Keenetic Hero DSL KN-2410 |
| **SoC** | EcoNet EN7516G |
| **CPU** | MIPS 1004Kc (MIPS32r2, big-endian) |
| **ABI** | o32, soft-float |
| **Ядро** | Linux 4.9 |
| **libc** | glibc 2.27 (Entware mips-3.4) |
| **ОЗУ** | 256 МБ |

## Зачем нужны патчи

В дереве зависимостей Vaultwarden используется `std::sync::atomic::AtomicU64`, которого **нет** на 32-битном MIPS. Сейчас патчи нужны трём крейтам:

| Крейт | Проблема | Решение |
|-------|----------|---------|
| `cached` | Использует `AtomicU64` для счётчиков кэша | `portable-atomic` с fallback через мьютекс |
| `mea` | Использует `AtomicU64` для асинхронной синхронизации | `portable-atomic` с fallback через мьютекс |
| `getrandom` | Напрямую вызывает `getrandom(2)` и получает `ENOSYS` на ядре Keenetic | Принудительный fallback на `/dev/urandom` для MIPS |

Кроме того, стандартная библиотека Rust (собирается из исходников через `-Z build-std`) использует 64-битные атомики внутренне, что требует `libatomic.so.1` в рантайме.

## Быстрый старт

```bash
# 1. Клонировать этот репозиторий
git clone https://github.com/MusubaPy/vaultwarden-keenetic.git
cd vaultwarden-keenetic

# 2. Установить Rust nightly и Entware SDK (см. Предварительные требования)

# 3. Собрать MIPS-бинарник локально на ПК
./scripts/build.sh

# 4. Выполнить первичную установку
ROUTER=root@ROUTER_IP SSH_PORT=222 ./scripts/deploy.sh
```

Скрипт сборки сам управляет исходниками Vaultwarden в `build/source`. На роутере компиляция не выполняется.

После первичной установки настройте доверенный HTTPS через KeenDNS по инструкции ниже. Последующие обновления выполняются одной командой:

```bash
./scripts/update.sh
```

Скрипт обновления получает актуальные исходники Vaultwarden, применяет MIPS-патчи, повторно использует готовый бинарник при неизменных входных данных, загружает его на роутер, перезапускает службу, проверяет порт `8080` и автоматически возвращает предыдущий бинарник при ошибке. Рабочий init-скрипт, `ADMIN_TOKEN`, база данных, вложения и остальные постоянные данные не перезаписываются.

## Доверенный HTTPS через KeenDNS

Не используйте самоподписанный сертификат Vaultwarden для мобильных клиентов. Браузер может разрешить ручное исключение, но приложения Bitwarden обычно требуют сертификат, которому доверяет операционная система. KeenDNS может завершать доверенное HTTPS-соединение на роутере и проксировать запросы к Vaultwarden внутри локальной сети.

### 1. Создайте домен веб-приложения

В веб-интерфейсе Keenetic:

1. Откройте **Сетевые правила** > **Доменное имя** > **KeenDNS**.
2. Настройте имя роутера KeenDNS, если его ещё нет, например `example.keenetic.pro`.
3. В разделе **Доступ к веб-приложениям домашней сети** нажмите **Добавить**.
4. Выберите сам роутер Keenetic в качестве устройства, поскольку Vaultwarden работает на роутере.
5. Укажите поддомен, например `vaultwarden`.
6. Для доступа из Интернета выберите **Без ограничений**.
7. Укажите TCP-порт `8080`.
8. Сохраните правило.

Итоговый публичный адрес будет выглядеть так:

```text
https://vaultwarden.example.keenetic.pro
```

Используйте точный созданный адрес в Vaultwarden и во всех клиентах Bitwarden. Не добавляйте `:8080` к публичному URL.

### 2. Настройте Vaultwarden за прокси KeenDNS

Измените `/opt/etc/init.d/S91vaultwarden` на роутере, чтобы сетевые параметры соответствовали этой схеме:

```sh
export ROCKET_ADDRESS=0.0.0.0
export ROCKET_PORT=8080
export DOMAIN=https://vaultwarden.example.keenetic.pro
```

HTTPS должен завершаться на KeenDNS. Удалите или закомментируйте экспорт `ROCKET_TLS`, чтобы Vaultwarden обслуживал обычный HTTP только на внутреннем порту:

```sh
# ROCKET_TLS намеренно отключён: HTTPS завершается на KeenDNS.
```

Перезапустите и проверьте службу:

```sh
/opt/etc/init.d/S91vaultwarden restart
/opt/etc/init.d/S91vaultwarden status
```

После этого откройте публичный адрес KeenDNS. Браузер и мобильное приложение должны принять сертификат без предупреждения.

### 3. Защитите установку

После создания нужного аккаунта:

1. Установите `SIGNUPS_ALLOWED=false` в `/opt/etc/init.d/S91vaultwarden`.
2. Создайте Argon2id PHC-строку командой `/opt/bin/vaultwarden hash`.
3. Сохраните полную PHC-строку в `ADMIN_TOKEN`, заключив её в одинарные кавычки.
4. Перезапустите Vaultwarden и входите в `/admin` с исходным паролем, использованным при создании хеша, а не с PHC-строкой.

Никогда не добавляйте рабочий `ADMIN_TOKEN`, закрытые TLS-ключи или каталог данных Vaultwarden в этот репозиторий.

## Предварительные требования

### Rust

```bash
curl https://sh.rustup.rs -sSf | sh
rustup toolchain install nightly
rustup +nightly component add rust-src
```

### Entware SDK

Скачать тулчейн MIPS32r2 с [wiki Entware](https://wiki.keenetic.com/entware) и распаковать в `~/tmp/entware-sdk`:

```bash
# Ожидаемая структура:
ls ~/tmp/entware-sdk/staging_dir/toolchain-mips_mips32r2_gcc-8.4.0_glibc-2.27/
```

### Исходники Vaultwarden

Отдельно клонировать исходники не требуется. `scripts/build.sh` сам клонирует и обновляет Vaultwarden в `build/source`.

## Структура проекта

```text
vaultwarden-keenetic/
├── vendor/                  # Запатченные исходники крейтов для сборки
│   ├── cached/              #   AtomicU64 заменён на portable-atomic
│   ├── mea/                 #   AtomicU64 заменён на portable-atomic
│   └── getrandom/           #   MIPS fallback на /dev/urandom
├── patches/                 # Исторические и справочные diff-патчи
├── scripts/
│   ├── build.sh             # Исходники, патчи и кросс-компиляция
│   ├── deploy.sh            # Первичная установка
│   ├── update.sh            # Безопасное обновление с откатом
│   └── gen-tls.sh           # Необязательный самоподписанный сертификат
├── config/
│   ├── .cargo/config.toml   # Шаблон кросс-компиляции Cargo
│   └── S91vaultwarden       # Начальный шаблон службы Entware
└── .github/workflows/
    └── build.yml
```

## Переменные окружения

Рабочие значения хранятся в `/opt/etc/init.d/S91vaultwarden` на роутере. `scripts/update.sh` сохраняет этот файл без изменений.

| Переменная | Рекомендуемое значение | Описание |
|-----------|-------------------------|----------|
| `ROCKET_PORT` | `8080` | Внутренний порт прослушивания |
| `ROCKET_ADDRESS` | `0.0.0.0` | Нужен для доступа прокси KeenDNS к службе |
| `DOMAIN` | `https://vaultwarden.example.keenetic.pro` | Точный публичный URL веб-приложения KeenDNS |
| `ADMIN_TOKEN` | Argon2id PHC-строка | Хеш для аутентификации в админ-панели |
| `SIGNUPS_ALLOWED` | `false` после создания аккаунта | Запрещает публичную регистрацию |
| `ICON_SERVICE` | `internal` | Проксирование иконок для систем с малым объёмом ОЗУ |
| `LOG_LEVEL` | `warn` | Минимальное логирование |

## Управление на роутере

```bash
ssh -p 222 root@ROUTER_IP

/opt/etc/init.d/S91vaultwarden status    # Статус
/opt/etc/init.d/S91vaultwarden restart   # Перезапуск
/opt/etc/init.d/S91vaultwarden stop      # Остановка

tail -f /opt/var/log/vaultwarden.log     # Логи в реальном времени
/opt/bin/vaultwarden hash                # Генерация хеша токена администратора
```

## Обновление Vaultwarden

Запускайте скрипт из этого репозитория на ПК сборки:

```bash
ROUTER=root@ROUTER_IP SSH_PORT=222 ./scripts/update.sh
```

Пароль роутера запрашивается один раз благодаря переиспользованию SSH-соединения. Компиляция всегда выполняется на ПК. Если commit upstream, тулчейн, входные файлы Cargo и MIPS-патчи не изменились, используется существующий бинарник. На роутер сначала загружается временный бинарник, предыдущая версия сохраняется для отката, а конфигурация и данные остаются без изменений.

Логи сборки и роутера при необходимости сохраняются локально в `build/`:

```text
build/cargo-build.log
build/router-vaultwarden.log
```

## Технические заметки

### AtomicU64 на MIPS32

MIPS32r2 не имеет нативных 64-битных атомарных инструкций. Крейт `portable-atomic` предоставляет fallback на мьютексах, используемый при включённой фиче `fallback`. Это добавляет пренебрежимый оверхед для счётчиков кэша и отслеживания длины контента.

### getrandom на Linux 4.9

Ядро Keenetic не предоставляет syscall `getrandom(2)` (добавлен для MIPS в Linux 4.7, но может быть отключён в прошивке Keenetic). Запатченный крейт `getrandom` принудительно использует файловый fallback через `/dev/urandom`.

### libatomic.so.1

Стандартная библиотека Rust (собирается из исходников через `-Z build-std`) использует `__atomic_*` builtins для внутренних 64-битных операций. Они предоставляются GCC `libatomic`. Статическая линковка не работает в PIE-бинарниках (нет `-fPIC` в `libatomic.a` тулчейна), поэтому shared-библиотека (~102 КБ) должна присутствовать на роутере.

### Оптимизация памяти

При 256 МБ ОЗУ помогают:
- `LOG_LEVEL=warn` — минимальное логирование
- `ICON_SERVICE=internal` — избегает внешних HTTP-запросов для иконок
- `panic=abort` — меньший бинарник, без раскрутки стека
- `strip=debuginfo` — удаление отладочных символов

## Лицензия

Проект распространяется под лицензией [MIT](LICENSE).

Vaultwarden распространяется под лицензией [AGPL-3.0](https://github.com/dani-garcia/vaultwarden/blob/main/LICENSE.txt).
