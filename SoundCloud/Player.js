(() => {
  if (!/(^|\.)soundcloud\.com$/.test(location.hostname)) return;

  const post = (message) => window.webkit.messageHandlers.player.postMessage(message);

  const media = new Set();
  // Set when the Mac goes to sleep; any playback that starts before the user
  // interacts again is treated as unwanted and paused.
  let suspended = false;
  // When the Mac wakes up, WebKit resumes media interrupted by sleep by sending
  // a "play" action of its own, which must not be mistaken for the user's.
  let sleeping = false;
  let wokeAt = 0;
  const isWakingUp = () => sleeping || Date.now() - wokeAt < 1500;

  const playButton = () => document.querySelector(".playControls__play");
  const isPlaying = () => {
    const button = playButton();
    if (button) return button.classList.contains("playing");
    return [...media].some((element) => !element.paused);
  };

  const togglePlayback = () => playButton()?.click();

  const pause = () => {
    if (playButton()?.classList.contains("playing")) togglePlayback();
    media.forEach((element) => element.pause());
  };

  const report = () => {
    const playing = [...media].some((element) => !element.paused && !element.ended);
    post({ playing });
  };

  const resume = () => { suspended = false; };
  window.addEventListener("pointerdown", resume, true);
  window.addEventListener("keydown", resume, true);

  window.desktopPlayer = {
    suspend() {
      suspended = true;
      sleeping = true;
      pause();
    },
    wake() {
      sleeping = false;
      wokeAt = Date.now();
    },
  };

  // Control Center and the keyboard media keys go through the Media Session API.
  // SoundCloud only registers play/pause there, so macOS falls back to +/-15s skip buttons.
  const session = navigator.mediaSession;

  const handlers = {
    play: () => {
      if (suspended && isWakingUp()) return;
      resume();
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
    element.addEventListener("playing", () => {
      if (suspended) pause();
      registerHandlers();
      report();
    });
    element.addEventListener("pause", report);
    element.addEventListener("ended", report);
  };

  // The window title bar takes the color of SoundCloud's header.
  let pageColor = "";
  const reportPageColor = () => {
    const header = document.querySelector("header.header");
    if (!header) return false;
    const [r, g, b, a = 1] = getComputedStyle(header).backgroundColor.match(/[\d.]+/g)?.map(Number) ?? [];
    if (r === undefined || a === 0) return false;
    const color = `${r},${g},${b}`;
    if (color !== pageColor) {
      pageColor = color;
      post({ color: [r, g, b] });
    }
    return true;
  };

  // Wait for the header to render, then only follow theme switches on <body>.
  const pageObserver = new MutationObserver(() => {
    if (!reportPageColor()) return;
    pageObserver.disconnect();
    new MutationObserver(reportPageColor).observe(document.body, { attributes: true, attributeFilter: ["class"] });
  });
  pageObserver.observe(document, { childList: true, subtree: true });

  const originalPlay = HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play = function (...args) {
    track(this);
    return originalPlay.apply(this, args);
  };

  document.addEventListener("play", (event) => {
    if (event.target instanceof HTMLMediaElement) track(event.target);
  }, true);
})();
