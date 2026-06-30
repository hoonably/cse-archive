#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEXGL_URL="https://github.com/BKcore/HexGL.git"
HEXGL_COMMIT="6addc95a2fce3bf05f4d751823cc054c61a16d68"
TARGET_DIR="$REPO_ROOT/HexGL"

mkdir -p "$(dirname "$TARGET_DIR")"

if [[ -d "$TARGET_DIR/.git" ]]; then
  current_commit="$(git -C "$TARGET_DIR" rev-parse HEAD)"
  if [[ "$current_commit" != "$HEXGL_COMMIT" ]]; then
    git -C "$TARGET_DIR" fetch --depth 1 origin "$HEXGL_COMMIT"
    git -C "$TARGET_DIR" checkout --detach "$HEXGL_COMMIT"
  fi
elif [[ -e "$TARGET_DIR" ]]; then
  echo "Refusing to overwrite non-git path: $TARGET_DIR" >&2
  exit 1
else
  git clone --depth 1 "$HEXGL_URL" "$TARGET_DIR"
  git -C "$TARGET_DIR" fetch --depth 1 origin "$HEXGL_COMMIT"
  git -C "$TARGET_DIR" checkout --detach "$HEXGL_COMMIT"
fi

INDEX_HTML="$TARGET_DIR/index.html"
LAUNCH_JS="$TARGET_DIR/launch.js"
LOADER_JS="$TARGET_DIR/bkcore/threejs/Loader.js"
IMAGE_DATA_JS="$TARGET_DIR/bkcore.coffee/ImageData.js"

perl -0pi -e 's#\s*<script type="text/javascript">\s*//analytics.*?</script>\s*##s' "$INDEX_HTML"
perl -0pi -e 's#href="http://hexgl\.bkcore\.com/favicon\.png"#href="favicon.png"#g' "$INDEX_HTML"
perl -0pi -e 's#\n\s*e\.crossOrigin = "anonymous";##g' "$LOADER_JS"
perl -0pi -e 's#\n\s*this\.image\.crossOrigin = "anonymous";##g' "$IMAGE_DATA_JS"
perl -0pi -e 's#THREE\.ImageUtils=\{crossOrigin:"anonymous"#THREE.ImageUtils={crossOrigin:null#g' "$TARGET_DIR/libs/Three.dev.js" "$TARGET_DIR/libs/Three.r53.js"
perl -0pi -e 's#a\[3\] = \(_ref = u\(a\[0\]\)\) != null \? _ref : a\[2\];#a[3] = (_ref = u(a[0])) != null ? parseInt(_ref, 10) : a[2];\n    if (isNaN(a[3])) {\n      a[3] = a[2];\n    }#' "$LAUNCH_JS"

if ! grep -q 'overflow:hidden;' "$INDEX_HTML"; then
  perl -0pi -e 's@(\s*body \{\n\s*padding:0;\n\s*margin:0;\n)@$1        overflow:hidden;\n        background:#000;\n@' "$INDEX_HTML"
fi

if ! grep -q 'ubiclaw-webview-stage' "$INDEX_HTML"; then
  perl -0pi -e 's@(\s*</style>)@\n      /* ubiclaw-webview-stage */\n      html, body {\n        width:100%;\n        height:100%;\n        background:#000;\n      }\n      #step-4, #main {\n        position:absolute;\n        inset:0;\n        overflow:hidden;\n        background:#000;\n      }\n      #main canvas {\n        display:block;\n        width:100% !important;\n        height:100% !important;\n      }\n$1@' "$INDEX_HTML"
fi

if ! grep -q 'ubiclaw-bridge.js' "$INDEX_HTML"; then
  perl -0pi -e 's#\n\s*</body>#\n    <script src="ubiclaw-bridge.js"></script>\n\n  </body>#' "$INDEX_HTML"
fi

perl -0pi -e 's#\n\s*<script src="ubiclaw-audio-shim\.js"></script>##g' "$INDEX_HTML"

cat > "$TARGET_DIR/ubiclaw-bridge.js" <<'EOF'
(function() {
  'use strict';

  if (window.__ubiclawHexGLBridgeInstalled) return;
  window.__ubiclawHexGLBridgeInstalled = true;

  var bridge = window.webkit && window.webkit.messageHandlers
    ? window.webkit.messageHandlers.ubiclawHexGL
    : null;
  var lastFramePost = 0;
  var framePostIntervalMs = 0;
  var hasReportedRunning = false;
  var lastStepStatus = '';
  var hasReportedFreeRun = false;
  var hasReportedGameSettings = false;
  var startRequested = false;
  var audioMasterVolume = parseInitialAudioVolume();

  function post(message) {
    if (!bridge) return;
    try {
      bridge.postMessage(message);
    } catch (error) {
      bridge = null;
    }
  }

  function stringify(value) {
    try {
      if (typeof value === 'string') return value;
      if (value && value.message) return value.message;
      return JSON.stringify(value);
    } catch (error) {
      return String(value);
    }
  }

  function status(value) {
    post({ type: 'status', value: value });
  }

  function debug(value) {
    post({ type: 'debug', value: value });
  }

  function error(value) {
    post({ type: 'error', value: value });
  }

  function clampAudioVolume(value) {
    value = Number(value);
    if (!isFinite(value)) return 1;
    return Math.max(0, Math.min(1, value));
  }

  function parseInitialAudioVolume() {
    try {
      return clampAudioVolume(new URLSearchParams(window.location.search).get('ubiclawAudioVolume'));
    } catch (error) {
      return 1;
    }
  }

  function applySoundVolume(sound) {
    if (!sound) return;
    var baseVolume = typeof sound.__ubiclawBaseVolume === 'number'
      ? sound.__ubiclawBaseVolume
      : 1;
    var effectiveVolume = Math.max(0, baseVolume * audioMasterVolume);
    if (sound.gainNode && sound.gainNode.gain) {
      sound.gainNode.gain.value = effectiveVolume;
    } else if (typeof sound.volume !== 'undefined') {
      sound.volume = effectiveVolume;
    }
  }

  function applyAllAudioVolumes() {
    if (!window.bkcore || !bkcore.Audio || !bkcore.Audio.sounds) return;
    for (var id in bkcore.Audio.sounds) {
      if (Object.prototype.hasOwnProperty.call(bkcore.Audio.sounds, id)) {
        applySoundVolume(bkcore.Audio.sounds[id]);
      }
    }
  }

  window.ubiclawSetAudioVolume = function(value) {
    audioMasterVolume = clampAudioVolume(value);
    applyAllAudioVolumes();
    return true;
  };

  function shouldSuppressSystemKeySound(event) {
    if (event.metaKey || event.ctrlKey || event.altKey) return false;
    return (event.keyCode || event.which || 0) !== 0;
  }

  function focusGameSurface() {
    var target = document.getElementById('main') || document.body || document.documentElement;
    if (!target || !target.focus) return;
    if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
    try {
      target.focus({ preventScroll: true });
    } catch (error) {
      target.focus();
    }
  }

  function resumeAudioContext() {
    if (!window.bkcore || !bkcore.Audio || !bkcore.Audio._ctx) return;
    var ctx = bkcore.Audio._ctx;
    if (ctx.state === 'suspended' && ctx.resume) {
      try {
        var result = ctx.resume();
        if (result && result.catch) result.catch(function() {});
      } catch (error) {}
    }
  }

  function preventSystemKeySound(event) {
    if (!shouldSuppressSystemKeySound(event)) return;
    event.preventDefault();
    resumeAudioContext();
  }

  function installInputAndAudioGuards() {
    document.addEventListener('keydown', preventSystemKeySound, true);
    document.addEventListener('keyup', preventSystemKeySound, true);
    document.addEventListener('mousedown', function() {
      focusGameSurface();
      resumeAudioContext();
    }, true);
    document.addEventListener('touchstart', function() {
      focusGameSurface();
      resumeAudioContext();
    }, true);
  }

  function installAudioControlsHook() {
    if (!window.bkcore || !bkcore.Audio || !bkcore.Audio.play || !bkcore.Audio.volume || !bkcore.Audio.addSound) {
      window.setTimeout(installAudioControlsHook, 50);
      return;
    }
    if (bkcore.Audio.__ubiclawAudioControlsHooked) return;
    var originalAddSound = bkcore.Audio.addSound;
    var originalPlay = bkcore.Audio.play;
    var originalVolume = bkcore.Audio.volume;
    bkcore.Audio.addSound = function(src, id, loop, callback, usePanner) {
      var wrappedCallback = function() {
        if (bkcore.Audio.sounds[id] && typeof bkcore.Audio.sounds[id].__ubiclawBaseVolume !== 'number') {
          bkcore.Audio.sounds[id].__ubiclawBaseVolume = 1;
        }
        applyAllAudioVolumes();
        if (callback) return callback.apply(this, arguments);
      };
      var result = originalAddSound.call(this, src, id, loop, wrappedCallback, usePanner);
      if (bkcore.Audio.sounds[id] && typeof bkcore.Audio.sounds[id].__ubiclawBaseVolume !== 'number') {
        bkcore.Audio.sounds[id].__ubiclawBaseVolume = 1;
      }
      applySoundVolume(bkcore.Audio.sounds[id]);
      return result;
    };
    bkcore.Audio.play = function() {
      resumeAudioContext();
      var result = originalPlay.apply(this, arguments);
      applyAllAudioVolumes();
      return result;
    };
    bkcore.Audio.volume = function(id, volume) {
      if (bkcore.Audio.sounds[id]) {
        bkcore.Audio.sounds[id].__ubiclawBaseVolume = clampAudioVolume(volume);
      }
      return originalVolume.call(this, id, clampAudioVolume(volume) * audioMasterVolume);
    };
    bkcore.Audio.__ubiclawAudioControlsHooked = true;
    window.ubiclawSetAudioVolume(audioMasterVolume);
    debug('audio_controls_hooked');
  }

  window.addEventListener('error', function(event) {
    error((event.message || 'JavaScript error') + ' @ ' + (event.filename || 'inline') + ':' + (event.lineno || 0));
  });

  window.addEventListener('unhandledrejection', function(event) {
    error('Unhandled promise rejection: ' + stringify(event.reason));
  });

  var originalConsoleError = console.error;
  console.error = function() {
    var args = Array.prototype.slice.call(arguments).map(stringify).join(' ');
    error(args);
    return originalConsoleError.apply(console, arguments);
  };

  function isDisplayed(element) {
    if (!element) return false;
    return window.getComputedStyle(element).display !== 'none';
  }

  function visibleStep() {
    var ids = ['step-1', 'step-2', 'step-3', 'step-4', 'step-5'];
    for (var i = 0; i < ids.length; i++) {
      if (isDisplayed(document.getElementById(ids[i]))) return ids[i];
    }
    return 'unknown';
  }

  function hasVisibleCanvas() {
    var canvas = document.querySelector('#main canvas');
    var step4 = document.getElementById('step-4');
    return !!(canvas && isDisplayed(step4));
  }

  function frame() {
    var now = performance.now();
    if (now - lastFramePost >= framePostIntervalMs) {
      lastFramePost = now;
      post({ type: 'frame' });
    }
  }

  function postFrameIfRunning() {
    if (hasVisibleCanvas()) {
      if (!hasReportedRunning) {
        hasReportedRunning = true;
        status('Running');
      }
      frame();
    }
  }

  function frameLoop() {
    postFrameIfRunning();
    window.requestAnimationFrame(frameLoop);
  }

  function reportStep() {
    var step = visibleStep();
    if (step !== lastStepStatus) {
      lastStepStatus = step;
      debug('visible_step=' + step);
      if (step === 'step-3') status('Loading assets');
      if (step === 'step-4') status('Game visible');
      if (step === 'step-5') status('Finished');
    }
    window.setTimeout(reportStep, 500);
  }

  function clickElement(element) {
    if (!element) return false;
    element.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
    return true;
  }

  function isFreeRunRequested() {
    return new URLSearchParams(window.location.search).get('ubiclawFreeRun') === '1';
  }

  function recoverShip(shipControls) {
    if (!shipControls) return;
    shipControls.destroyed = false;
    shipControls.falling = false;
    shipControls.active = true;
    shipControls.shield = shipControls.maxShield || 1;
    if (shipControls.collision) {
      shipControls.collision.front = false;
      shipControls.collision.left = false;
      shipControls.collision.right = false;
    }
    if (shipControls.speed && shipControls.maxSpeed) {
      shipControls.speed = Math.min(shipControls.speed, shipControls.maxSpeed * 0.35);
    }
  }

  function installFreeRunMode() {
    if (!isFreeRunRequested()) return;
    if (!window.bkcore || !bkcore.hexgl || !bkcore.hexgl.ShipControls || !bkcore.hexgl.Gameplay) {
      window.setTimeout(installFreeRunMode, 50);
      return;
    }

    var shipPrototype = bkcore.hexgl.ShipControls.prototype;
    if (!shipPrototype.__ubiclawFreeRunPatched) {
      shipPrototype.destroy = function() {
        recoverShip(this);
      };
      shipPrototype.fall = function() {
        recoverShip(this);
        if (this.repulsionForce) this.repulsionForce.z = -Math.max(this.repulsionAmount || 0.8, 1.0);
      };
      shipPrototype.__ubiclawFreeRunPatched = true;
    }

    var gameplayPrototype = bkcore.hexgl.Gameplay.prototype;
    if (!gameplayPrototype.__ubiclawFreeRunPatched) {
      var originalStart = gameplayPrototype.start;
      gameplayPrototype.start = function() {
        var result = originalStart.apply(this, arguments);
        this.maxLaps = 1;
        if (this.hud) this.hud.updateLap(this.lap, this.maxLaps);
        return result;
      };

      var originalEnd = gameplayPrototype.end;
      gameplayPrototype.end = function(result) {
        if (result === this.results.DESTROYED || result === this.results.WRONGWAY) {
          this.result = this.results.NONE;
          this.step = 4;
          recoverShip(this.shipControls);
          if (this.hud) this.hud.display('Recovered', 0.4);
          return;
        }
        return originalEnd.apply(this, arguments);
      };
      gameplayPrototype.__ubiclawFreeRunPatched = true;
    }

    if (!hasReportedFreeRun) {
      hasReportedFreeRun = true;
      debug('free_run_mode=on');
    }
  }

  function reportGameSettings() {
    if (hasReportedGameSettings) return;
    if (!window.hexGL || !hasVisibleCanvas()) {
      window.setTimeout(reportGameSettings, 100);
      return;
    }

    hasReportedGameSettings = true;
    debug(
      'hexgl_settings=quality=' + window.hexGL.quality +
      ',displayHUD=' + window.hexGL.displayHUD +
      ',hud=' + (!!window.hexGL.hud) +
      ',godmode=' + window.hexGL.godmode
    );
  }

  function hookRenderLoop() {
    if (!window.bkcore || !bkcore.hexgl || !bkcore.hexgl.HexGL) {
      window.setTimeout(hookRenderLoop, 50);
      return;
    }

    var originalUpdate = bkcore.hexgl.HexGL.prototype.update;
    if (originalUpdate.__ubiclawHooked) return;

    bkcore.hexgl.HexGL.prototype.update = function() {
      var result = originalUpdate.apply(this, arguments);
      return result;
    };
    bkcore.hexgl.HexGL.prototype.update.__ubiclawHooked = true;
    debug('hexgl_update_hooked');
  }

  function startHexGLWhenReady(startDelayMs) {
    if (startRequested || hasVisibleCanvas()) return true;
    startRequested = true;

    startDelayMs = Number(startDelayMs || 0);
    if (!isFinite(startDelayMs) || startDelayMs < 0) startDelayMs = 0;
    var deadline = performance.now() + startDelayMs + 7000;
    if (startDelayMs > 0) {
      status('Resting');
      debug('auto_start_delay_ms=' + Math.round(startDelayMs));
    }

    function clickStart() {
      var start = document.getElementById('start');
      if (!start) {
        if (performance.now() < deadline) window.setTimeout(clickStart, 50);
        return;
      }
      if (start.textContent.indexOf('not supported') >= 0) {
        status('WebGL unavailable');
        return;
      }

      status('Starting');
      focusGameSurface();
      resumeAudioContext();
      clickElement(start);
      waitForContinue();
    }

    function waitForContinue() {
      var continueStep = document.getElementById('step-2');
      if (continueStep && isDisplayed(continueStep)) {
        window.setTimeout(function() {
          status('Loading assets');
          focusGameSurface();
          resumeAudioContext();
          clickElement(continueStep);
        }, 120);
        return;
      }
      if (performance.now() < deadline) {
        window.setTimeout(waitForContinue, 50);
      } else {
        error('Auto-start timed out waiting for step-2');
      }
    }

    window.setTimeout(clickStart, startDelayMs + 150);
    return true;
  }

  function autoStartIfRequested() {
    var params = new URLSearchParams(window.location.search);
    if (params.get('ubiclawAutoStart') !== '1') return;
    startHexGLWhenReady(params.get('ubiclawAutoStartDelayMs') || 0);
  }

  installInputAndAudioGuards();
  installAudioControlsHook();
  window.requestAnimationFrame(frameLoop);
  window.ubiclawStartHexGLWhenReady = startHexGLWhenReady;
  reportStep();
  hookRenderLoop();
  installFreeRunMode();
  reportGameSettings();
  status('Loaded');
  autoStartIfRequested();
})();
EOF

cat > "$TARGET_DIR/UBICLAW_NOTES.md" <<EOF
# HexGL Local Setup Notes

Prepared by \`Scripts/setup_hexgl.sh\` for UbiClaw foreground workload experiments.

- Source: $HEXGL_URL
- Commit: \`$HEXGL_COMMIT\`
- Upstream author: Thibaut Despoulain / BKcore
- Root license: MIT, see \`LICENSE\`

Local changes:

- Removed the Google Analytics loader and remote favicon URLs from \`index.html\`.
- Added \`ubiclaw-bridge.js\` to auto-start the game when requested and forward render-loop frame events to the macOS app via \`WKScriptMessageHandler\`.

License notes:

- Some HexGL source files still contain older Creative Commons Attribution-NonCommercial 3.0 comments.
- \`audio/LICENSE\` lists separate attribution/public-domain notes for the bundled sound files.
- Keep \`LICENSE\`, \`audio/LICENSE\`, and this file with local builds that include HexGL.
EOF

echo "HexGL is ready at $TARGET_DIR"
