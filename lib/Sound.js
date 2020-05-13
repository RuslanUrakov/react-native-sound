"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const tslib_1 = require("tslib");
const react_native_macos_1 = require("react-native-macos");
const RNSound_1 = require("./RNSound");

const Sound = /** @class */ (function() {
  function Sound(_a) {
    const { source, onLoad, onError } = _a;
    const opts = tslib_1.__rest(_a, ["source", "onLoad", "onError"]);
    this._lastPlayed = 0;
    this._disposed = false;
    this._source = this._resolveSource(source);
    this._props = tslib_1.__assign(
      { timeout: 0, volume: 1, muted: false, loops: false },
      opts
    );
    RNSound_1.RNSound.preload(this._source).then(
      onLoad,
      onError ||
        function(error) {
          throw error;
        }
    );
  }
  Object.defineProperty(Sound.prototype, "source", {
    /** The bundled sound asset. */
    get: function() {
      return this._source;
    },
    enumerable: true,
    configurable: true
  });
  Object.defineProperty(Sound.prototype, "timeout", {
    get: function() {
      return this._props.timeout;
    },
    enumerable: true,
    configurable: true
  });
  Object.defineProperty(Sound.prototype, "volume", {
    /** The volume limit, between 0 and 1. */
    get: function() {
      return this._props.volume;
    },
    set: function(val) {
      this._props.volume = val;
    },
    enumerable: true,
    configurable: true
  });
  Object.defineProperty(Sound.prototype, "muted", {
    /** Useful for muting a sound without affecting its `volume` prop. */
    get: function() {
      return this._props.muted;
    },
    set: function(val) {
      this._props.muted = val;
    },
    enumerable: true,
    configurable: true
  });
  /** Play the sound once. */
  Sound.prototype.play = function(options) {
    if (options === void 0) {
      options = {};
    }
    if (this.muted) {
      return;
    }
    const now = Date.now();
    if (this.timeout <= 0 || now - this._lastPlayed >= this.timeout) {
      this._lastPlayed = now;
      return RNSound_1.RNSound.play(
        tslib_1.__assign({ ...this._props }, options)
      );
    }
  };
  Sound.prototype.stop = function() {
    RNSound_1.RNSound.stop();
  };
  Sound.prototype.pause = function() {
    RNSound_1.RNSound.pause();
  };
  Sound.prototype.resume = function() {
    RNSound_1.RNSound.resume();
  };
  Sound.prototype.setVolume = function(volume) {
    RNSound_1.RNSound.setVolume(volume);
  };
  Sound.prototype._resolveSource = function(source) {
    const uri = react_native_macos_1.Image.resolveAssetSource(source).uri;
    if (!hasExtension(uri, ".wav") && !hasExtension(uri, ".mp3")) {
      throw Error('The "source" prop must have a .wav or .mp3 extension');
    }
    return uri;
  };
  return Sound;
})();
exports.Sound = Sound;
function hasExtension(uri, ext) {
  const queryIndex = uri.indexOf("?");
  return (queryIndex < 0 ? uri : uri.slice(0, queryIndex)).endsWith(ext);
}
