/*
 * Страница привязки телевизора к аккаунту sloosh.
 *
 * Открывается по QR-коду с телевизора: /pair/?c=<КОД>&n=<NONCE>
 *
 * 1. Читает узел media_stats/pairing/<sha256(код)> и проверяет, что код жив.
 * 2. Пользователь входит своим аккаунтом (Google или e-mail/пароль) через
 *    Firebase REST — так мы получаем refresh-токен, который браузерный SDK
 *    обычно не отдаёт.
 * 3. Шифрует refresh-токен ключом SHA-256("sloosh-pairing:" + код + ":" + nonce)
 *    в AES-GCM через WebCrypto и записывает шифротекст в узел.
 * 4. Телевизор расшифровывает его тем же ключом (nonce есть только в QR и на ТВ)
 *    и удаляет узел.
 *
 * Токен в открытом виде не покидает устройство, в базу попадает только шифротекст.
 */
(function () {
  'use strict';

  var FIREBASE_API_KEY = 'AIzaSyB2-pwth7wkTCVnVmwzdSUBPo9vGdMytsY';
  var RTDB = 'https://sloosh-77434-default-rtdb.firebaseio.com';
  var PAIRING_PATH = 'media_stats/pairing';
  var GOOGLE_CLIENT_ID = '535135371915-n2sr91it0ramcgv3078m8asvrf4dn0ri.apps.googleusercontent.com';

  var CODE_RE = /^[A-Z0-9]{8}$/;
  var NONCE_RE = /^[0-9a-f]{32}$/;
  var GOOGLE_WAIT_MS = 4000;

  var state = {
    code: null,
    nonce: null,
    hash: null,
    session: null,
    busy: false,
    googleReady: false
  };

  function el(id) {
    return document.getElementById(id);
  }

  function show(name) {
    ['loading', 'invalid', 'problem', 'auth', 'confirm', 'done'].forEach(function (view) {
      var node = el('view-' + view);
      if (!node) return;
      node.classList.toggle('hidden', view !== name);
    });
  }

  function problem(title, text) {
    el('problem-title').textContent = title;
    el('problem-text').textContent = text || '';
    show('problem');
  }

  function setText(id, text) {
    var node = el(id);
    if (node) node.textContent = text;
  }

  function error(id, text) {
    var node = el(id);
    if (!node) return;
    node.textContent = text || '';
    node.classList.toggle('hidden', !text);
  }

  function formatCode(code) {
    return code ? code.slice(0, 4) + '-' + code.slice(4) : '········';
  }

  // ─── Криптография ────────────────────────────────────────────────────────

  function requireCrypto() {
    if (!window.crypto || !window.crypto.subtle) {
      throw new Error('Браузер не поддерживает шифрование. Откройте ссылку в Safari или Chrome по https.');
    }
  }

  function sha256Hex(text) {
    var bytes = new TextEncoder().encode(text);
    return crypto.subtle.digest('SHA-256', bytes).then(function (buffer) {
      return Array.prototype.map.call(new Uint8Array(buffer), function (b) {
        return b.toString(16).padStart(2, '0');
      }).join('');
    });
  }

  function bytesToBase64(bytes) {
    var binary = '';
    for (var i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary);
  }

  /**
   * Ключ = SHA-256("sloosh-pairing:" + код + ":" + nonce).
   * Точно та же схема в PairingService.kt на телевизоре — менять синхронно.
   */
  function encryptGrant(refreshToken, code, nonce) {
    requireCrypto();
    var material = new TextEncoder().encode('sloosh-pairing:' + code + ':' + nonce);
    return crypto.subtle.digest('SHA-256', material).then(function (digest) {
      return crypto.subtle.importKey('raw', digest, { name: 'AES-GCM' }, false, ['encrypt']);
    }).then(function (key) {
      var iv = crypto.getRandomValues(new Uint8Array(12));
      return crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv }, key, new TextEncoder().encode(refreshToken))
        .then(function (cipher) {
          var payload = new Uint8Array(iv.length + cipher.byteLength);
          payload.set(iv, 0);
          payload.set(new Uint8Array(cipher), iv.length);
          return bytesToBase64(payload);
        });
    });
  }

  // ─── Сеть ────────────────────────────────────────────────────────────────

  function readJson(response) {
    return response.text().then(function (text) {
      if (!text) return {};
      try {
        return JSON.parse(text);
      } catch (e) {
        return {};
      }
    });
  }

  function firebaseMessage(payload) {
    var code = payload && payload.error && payload.error.message
      ? String(payload.error.message)
      : '';
    if (code.indexOf('INVALID_LOGIN_CREDENTIALS') >= 0 || code.indexOf('EMAIL_NOT_FOUND') >= 0) {
      return 'Неверный e-mail или пароль.';
    }
    if (code.indexOf('INVALID_PASSWORD') >= 0) {
      return 'Неверный пароль.';
    }
    if (code.indexOf('USER_DISABLED') >= 0) {
      return 'Аккаунт отключён.';
    }
    if (code.indexOf('TOO_MANY_ATTEMPTS') >= 0) {
      return 'Слишком много попыток. Подождите минуту.';
    }
    if (code.indexOf('INVALID_EMAIL') >= 0) {
      return 'Проверьте адрес e-mail.';
    }
    if (code.indexOf('OPERATION_NOT_ALLOWED') >= 0) {
      return 'Вход по паролю отключён на сервере. Зайдите через Google.';
    }
    if (code.indexOf('ACCOUNT_EXISTS_WITH_DIFFERENT_CREDENTIAL') >= 0) {
      return 'Этот e-mail уже привязан к другому способу входа. Войдите по e-mail и паролю.';
    }
    if (code.indexOf('INVALID_IDP_RESPONSE') >= 0) {
      return 'Google не принял вход. Попробуйте войти по e-mail.';
    }
    return null;
  }

  function loadNode() {
    var url = RTDB + '/' + PAIRING_PATH + '/' + state.hash + '.json';
    return fetch(url, { cache: 'no-store' }).then(function (res) {
      if (!res.ok) throw new Error('Нет связи с сервером. Проверьте интернет.');
      return readJson(res);
    }).then(function (node) {
      return node && Object.keys(node).length ? node : null;
    });
  }

  function signInWithIdp(googleIdToken) {
    var requestUri = location.origin + location.pathname;
    var body = {
      postBody: 'id_token=' + encodeURIComponent(googleIdToken) + '&providerId=google.com',
      requestUri: requestUri,
      returnIdpCredential: true,
      returnSecureToken: true
    };
    return fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=' + FIREBASE_API_KEY, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).then(function (res) {
      return readJson(res).then(function (payload) {
        if (!res.ok || !payload.idToken) {
          throw new Error(firebaseMessage(payload) || 'Не удалось войти через Google.');
        }
        return payload;
      });
    });
  }

  function signInWithPassword(email, password) {
    var body = { email: email, password: password, returnSecureToken: true };
    return fetch('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=' + FIREBASE_API_KEY, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    }).then(function (res) {
      return readJson(res).then(function (payload) {
        if (!res.ok || !payload.idToken) {
          throw new Error(firebaseMessage(payload) || 'Не удалось войти.');
        }
        return payload;
      });
    });
  }

  function refreshIdToken(refreshToken) {
    var body = 'grant_type=refresh_token&refresh_token=' + encodeURIComponent(refreshToken);
    return fetch('https://securetoken.googleapis.com/v1/token?key=' + FIREBASE_API_KEY, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body
    }).then(function (res) {
      return readJson(res).then(function (payload) {
        if (!res.ok || !payload.id_token) throw new Error('Сессия истекла, войдите заново.');
        return payload.id_token;
      });
    });
  }

  function patchGrant(idToken, grant) {
    var url = RTDB + '/' + PAIRING_PATH + '/' + state.hash + '.json?auth=' + encodeURIComponent(idToken);
    return fetch(url, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(grant)
    }).then(function (res) {
      if (res.status === 401 || res.status === 403) {
        var err = new Error('unauthorized');
        err.unauthorized = true;
        throw err;
      }
      if (!res.ok) {
        throw new Error('Не удалось передать подтверждение на телевизор.');
      }
      return true;
    });
  }

  // ─── Сценарий ────────────────────────────────────────────────────────────

  function boot() {
    show('loading');

    var params = new URLSearchParams(location.search);
    var code = (params.get('c') || '').trim().toUpperCase().replace(/[^A-Z0-9]/g, '');
    var nonce = (params.get('n') || '').trim().toLowerCase();

    if (!CODE_RE.test(code) || !NONCE_RE.test(nonce)) {
      show('invalid');
      return;
    }

    state.code = code;
    state.nonce = nonce;
    setText('code-chip-auth', formatCode(code));
    setText('code-chip-confirm', formatCode(code));

    sha256Hex(code)
      .then(function (hash) {
        state.hash = hash;
        return loadNode();
      })
      .then(function (node) {
        if (!node) {
          problem('Код не найден', 'Похоже, код уже обновился или телевизор перезапустился. Отсканируйте новый QR-код с экрана.');
          return;
        }
        if (node.status === 'granted') {
          problem('Код уже использован', 'Этот код уже подтвердили. На телевизоре должен быть новый код — отсканируйте его.');
          return;
        }
        if (node.expiresAt && Date.now() > Number(node.expiresAt)) {
          problem('Код истёк', 'Код живёт 5 минут. На телевизоре уже появился новый — отсканируйте его.');
          return;
        }
        show('auth');
        initGoogle();
      })
      .catch(function (err) {
        problem('Нет связи', err && err.message ? err.message : 'Проверьте интернет и попробуйте ещё раз.');
      });
  }

  // ─── Google ──────────────────────────────────────────────────────────────

  function waitForGoogle() {
    return new Promise(function (resolve) {
      var started = Date.now();
      (function poll() {
        if (window.google && window.google.accounts && window.google.accounts.id) {
          resolve(true);
          return;
        }
        if (Date.now() - started > GOOGLE_WAIT_MS) {
          resolve(false);
          return;
        }
        setTimeout(poll, 120);
      })();
    });
  }

  function initGoogle() {
    if (state.googleReady) return;
    waitForGoogle().then(function (ready) {
      if (!ready) {
        el('google-hint').classList.remove('hidden');
        return;
      }
      try {
        window.google.accounts.id.initialize({
          client_id: GOOGLE_CLIENT_ID,
          callback: onGoogleCredential,
          ux_mode: 'popup',
          auto_select: false,
          cancel_on_tap_outside: true
        });
        window.google.accounts.id.renderButton(el('google-slot'), {
          type: 'standard',
          theme: 'filled_black',
          size: 'large',
          text: 'continue_with',
          shape: 'pill',
          logo_alignment: 'left',
          locale: 'ru',
          width: 320
        });
        state.googleReady = true;
        // Если домен не авторизован в Google Cloud, кнопка молча не появится —
        // тогда честно показываем подсказку вместо пустого места.
        setTimeout(function () {
          var slot = el('google-slot');
          if (!slot || slot.children.length === 0) {
            el('google-hint').classList.remove('hidden');
          }
        }, 3500);
      } catch (e) {
        el('google-hint').classList.remove('hidden');
      }
    });
  }

  function onGoogleCredential(response) {
    if (state.busy) return;
    if (!response || !response.credential) {
      error('auth-error', 'Вход через Google отменён.');
      return;
    }
    state.busy = true;
    error('auth-error', '');
    signInWithIdp(response.credential)
      .then(onSignedIn)
      .catch(function (err) {
        error('auth-error', err && err.message ? err.message : 'Не удалось войти через Google.');
      })
      .then(function () {
        state.busy = false;
      });
  }

  function onSignedIn(payload) {
    if (!payload.refreshToken) {
      throw new Error('Сервер не выдал долгосрочный доступ. Попробуйте войти заново.');
    }
    state.session = {
      idToken: payload.idToken,
      refreshToken: payload.refreshToken,
      uid: payload.localId,
      email: payload.email || ''
    };
    setText('account-email', state.session.email || 'ваш аккаунт');
    error('auth-error', '');
    error('confirm-error', '');
    show('confirm');
  }

  function onEmailSubmit(event) {
    event.preventDefault();
    if (state.busy) return;

    var email = (el('email').value || '').trim();
    var password = el('password').value || '';
    if (!email || !password) {
      error('auth-error', 'Введите e-mail и пароль.');
      return;
    }

    state.busy = true;
    error('auth-error', '');
    var button = el('btn-email');
    button.disabled = true;
    button.textContent = 'Входим…';

    signInWithPassword(email, password)
      .then(onSignedIn)
      .catch(function (err) {
        error('auth-error', err && err.message ? err.message : 'Не удалось войти.');
      })
      .then(function () {
        state.busy = false;
        button.disabled = false;
        button.textContent = 'Войти';
      });
  }

  // ─── Подтверждение ───────────────────────────────────────────────────────

  function approve() {
    if (state.busy || !state.session) return;
    state.busy = true;
    error('confirm-error', '');

    var button = el('btn-approve');
    button.disabled = true;
    button.textContent = 'Подключаем…';

    var session = state.session;

    loadNode()
      .then(function (node) {
        if (!node) {
          throw new Error('Код не найден — отсканируйте новый QR-код с телевизора.');
        }
        if (node.status === 'granted') {
          throw new Error('Этот код уже подтверждён.');
        }
        if (node.expiresAt && Date.now() > Number(node.expiresAt)) {
          throw new Error('Код истёк — на телевизоре уже новый.');
        }
        return encryptGrant(session.refreshToken, state.code, state.nonce);
      })
      .then(function (ciphertext) {
        var grant = {
          status: 'granted',
          ct: ciphertext,
          uid: session.uid || '',
          grantedAt: Date.now(),
          device: 'web'
        };
        return patchGrant(session.idToken, grant).catch(function (err) {
          if (!err.unauthorized) throw err;
          return refreshIdToken(session.refreshToken).then(function (fresh) {
            session.idToken = fresh;
            return patchGrant(fresh, grant);
          });
        });
      })
      .then(function () {
        state.session = null;
        show('done');
      })
      .catch(function (err) {
        error('confirm-error', err && err.message ? err.message : 'Не удалось подтвердить вход.');
        button.disabled = false;
        button.textContent = 'Разрешить вход';
      })
      .then(function () {
        state.busy = false;
      });
  }

  function switchAccount() {
    state.session = null;
    try {
      if (window.google && window.google.accounts && window.google.accounts.id) {
        window.google.accounts.id.disableAutoSelect();
      }
    } catch (e) { /* не критично */ }
    el('password').value = '';
    error('auth-error', '');
    show('auth');
    initGoogle();
  }

  document.addEventListener('DOMContentLoaded', function () {
    el('form-email').addEventListener('submit', onEmailSubmit);
    el('btn-approve').addEventListener('click', approve);
    el('btn-switch').addEventListener('click', switchAccount);
    boot();
  });
})();
