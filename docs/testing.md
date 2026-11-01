# Ручная проверка

1. Открыть главную на телефоне и компьютере; проверить навигацию и отсутствие горизонтальной прокрутки.
2. «Бесплатно» показывает две карточки, «Для первого раза» — две. Несуществующий поисковый запрос показывает пустое состояние.
3. Сохранить карточку, перейти в «Мои планы», обновить страницу: карточка остаётся. Удалить её из планов.
4. Открыть описание, закрыть Escape, снова открыть. Проверить клавиатурный фокус.
5. Открыть приглашение. Сменить все три стиля, ввести кириллицу, emoji и символы < > &. Текст отображается как текст.
6. Скопировать ссылку, открыть в другом браузере: выставка, стиль и сообщение сохранены. Закрыть приглашение и перейти к афише.
7. Системный sharing доступен в поддерживаемых браузерах; иначе копируется ссылка. При запрете буфера отображается поле ручного копирования.
8. Рассылка не должна обещать успешную подписку или собирать email.

Публикация считается завершённой только после успешного deployment и ответа публичного сайта.

## Version 2

- Default language is English. Switching EN / HU / RU translates navigation, examples, dialogs, account and editor labels; the choice survives reload.
- With config empty, account inputs and publish/save controls are disabled. Editor preview works without creating an account or publishing a post.
- Untrusted story/message text must render literally, never as HTML.
- Configured backend checks and real delivery validation are listed in SETUP.md. They require provisioned services; they have not been run against a live project yet.
