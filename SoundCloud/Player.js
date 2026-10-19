(() => {
  if (!/(^|\.)soundcloud\.com$/.test(location.hostname)) return;

  const media = new Set();

  const playButton = () => document.querySelector(".playControls__play");
  const isPlaying = () => {
    const button = playButton();
    if (button) return button.classList.contains("playing");
    return [...media].some((element) => !element.paused);
  };

  const togglePlayback = () => playButton()?.click();

  // Control Center and the keyboard media keys go through the Media Session API.
  // SoundCloud only registers play/pause there, so macOS falls back to +/-15s skip buttons.
  const session = navigator.mediaSession;

  const handlers = {
    play: () => {
      if (!isPlaying()) togglePlayback();
    },
    pause: () => {
      if (isPlaying()) togglePlayback();
    },
    previoustrack: () => document.querySelector(".skipControl__previous")?.click(),
    nexttrack: () => document.querySelector(".skipControl__next")?.click(),
    seekbackward: null,
    seekforward: null,
  };

  const setActionHandler = session?.setActionHandler.bind(session);

  // WebKit drops registered commands while no media element exists,
  // so they have to be registered again once playback starts.
  const registerHandlers = () => {
    if (!setActionHandler) return;
    for (const [action, handler] of Object.entries(handlers)) {
      try {
        setActionHandler(action, handler);
      } catch {}
    }
  };

  if (session) {
    session.setActionHandler = (action, handler) => {
      if (!(action in handlers)) setActionHandler(action, handler);
    };
    registerHandlers();
  }

  const track = (element) => {
    if (media.has(element)) return;
    media.add(element);
    element.addEventListener("playing", registerHandlers);
  };

  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) {
    track(this);
    return originalPlay.apply(this, args);
  };

  document.addEventListener("play", (event) => {
    if (event.target instanceof HTMLMediaElement) track(event.target);
  }, true);
})();
