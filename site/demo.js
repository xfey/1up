(() => {
  "use strict";

  // Standalone browser demo. No storage, analytics, fonts, or network requests.
  // The app's 45 / 180 / 20 minute cycles are shown at 360× speed here.
  const speed = 360;
  const updateInterval = 5 * 60 * 1000 / speed;
  const flightDuration = 3200;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const stage = document.querySelector(".stage");
  const lanes = document.querySelector(".lanes");
  const playback = document.querySelector(".playback");
  const message = document.querySelector(".message");
  const feedback = document.querySelector("#feedback");
  const copy = {
    normal: "今天状态火热！",
    hp: "要不起来走走？",
    water: "喝杯水",
    san: "远眺一下，看看风景吧",
    empty: "身体是革命的本钱",
    happy: ["爱你老己", "身体健康 +1", "又缓过来一些啦"],
  };
  const patterns = {
    hp: ["001100001100", "011110011110", "111111111111", "111111111111", "111111111111", "011111111110", "001111111100", "000111111000", "000011110000", "000001100000"],
    water: ["011111111000", "010000001000", "010000001110", "010000001010", "010000001010", "010000001010", "010000001110", "010111101000", "010111101000", "010111101000", "001111110000"],
    san: ["0000000000000000", "0000000000111100", "0000000001111100", "0111100011111100", "0111110011111000", "0011111011110000", "0001111111100000", "0000011110000000", "0000001100000000", "0000001100000000", "0000001100000000", "0000001100000000", "0000001100000000", "0000000000000000", "0000000000000000", "0000000000000000"],
    flame: ["000000100000", "000001100000", "000011100000", "000011110000", "000111110100", "000111111100", "001111111110", "001111111110", "001111111110", "000111111100", "000111111100", "000011111000", "000000000000"],
  };

  function pixels(svg, rows, outline = false) {
    const size = svg.viewBox.baseVal;
    const dx = Math.floor((size.width - rows[0].length) / 2);
    const dy = Math.floor((size.height - rows.length) / 2);
    const occupied = (x, y) => rows[y]?.[x] === "1";
    rows.forEach((row, y) => [...row].forEach((bit, x) => {
      if (bit !== "1") return;
      if (outline && occupied(x - 1, y) && occupied(x + 1, y) && occupied(x, y - 1) && occupied(x, y + 1)) return;
      const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
      for (const [key, value] of Object.entries({ x: x + dx, y: y + dy, width: 1, height: 1, fill: "currentColor" })) {
        rect.setAttribute(key, value);
      }
      svg.append(rect);
    }));
  }

  const settings = {
    hp: { value: 70, minutes: 45, action: "起身走一走", label: "HP", period: 6000, nextHit: 4400 },
    water: { value: 30, minutes: 180, action: "喝一杯水", label: "水分", period: 10000, nextHit: 3200, continuous: true },
    san: { value: 50, minutes: 20, action: "远眺一会儿", label: "SAN", period: 4000, nextHit: 1200 },
  };
  const gauges = Object.entries(settings).map(([id, config]) => {
    const row = document.querySelector(`.row[data-gauge="${id}"]`);
    const meter = row.querySelector(".meter");
    pixels(row.querySelector("svg"), patterns[id]);
    const cells = Array.from({ length: 10 }, () => {
      const cell = document.createElement("span");
      cell.className = "cell";
      cell.setAttribute("aria-hidden", "true");
      const fill = document.createElement("span");
      fill.className = "fill";
      cell.append(fill);
      meter.append(cell);
      return fill;
    });
    const lane = document.createElement("div");
    lane.className = "lane";
    const note = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    note.setAttribute("class", "note");
    note.setAttribute("viewBox", "0 0 16 16");
    note.dataset.gauge = id;
    pixels(note, patterns[id]);
    const impact = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    impact.setAttribute("class", "impact");
    impact.setAttribute("viewBox", "0 0 24 24");
    impact.dataset.gauge = id;
    impact.innerHTML = '<path fill="currentColor" d="M10 1h4v5h-4z M18 10h5v4h-5z M10 18h4v5h-4z M1 10h5v4H1z"/>';
    // One reusable note per lane: there can never be more than three.
    lanes.append(lane, note, impact);
    const symbol = note.getBBox();
    const gauge = { ...config, id, row, meter, cells, lane, note, symbol, impact, impactStart: null, displayed: config.value, shown: config.value / 10, infusion: null, paddle: null, travel: 0 };
    row.querySelector("button").addEventListener("click", () => replenish(gauge));
    return gauge;
  });
  pixels(document.querySelector(".streak svg"), patterns.flame, true);

  let frame = 0;
  let happyUntil = 0;
  let feedbackIndex = 0;
  let lastFrame = performance.now();
  let demoTime = 0;
  let nextUpdate = updateInterval;
  let playing = !reducedMotion.matches;
  const easeOut = t => 1 - (1 - t) ** 3;

  function draw(gauge) {
    gauge.cells.forEach((cell, index) => {
      const fraction = Math.max(0, Math.min(1, gauge.shown - index));
      cell.style.setProperty("--fill", fraction);
      cell.style.filter = gauge.infusion && fraction > 0 && fraction < 1 ? "brightness(1.2)" : "";
    });
    gauge.row.querySelector(".grip").style.setProperty("--travel", gauge.travel);
    gauge.meter.setAttribute("aria-valuenow", Math.round(gauge.displayed));
  }

  function updateMessage(now) {
    if (now < happyUntil) return;
    const lowest = gauges.reduce((a, b) => a.displayed <= b.displayed ? a : b);
    message.textContent = copy[gauges.every(g => g.displayed <= 0) ? "empty" : lowest.displayed < 40 ? lowest.id : "normal"];
  }

  function replenish(gauge, automatic = false) {
    const now = performance.now();
    gauge.value = gauge.id === "water" ? Math.min(100, gauge.value + 100 / 3) : 100;
    gauge.displayed = gauge.value;
    const target = gauge.displayed / 10;
    if (reducedMotion.matches) {
      gauge.shown = target;
      gauge.infusion = gauge.paddle = null;
      gauge.travel = 0;
    } else {
      gauge.infusion = target > gauge.shown ? {
        from: gauge.shown, target, start: now,
        duration: 480 + Math.min(6, target - gauge.shown) * 40,
      } : null;
      gauge.paddle = { start: now, from: gauge.travel };
    }
    message.textContent = copy.happy[feedbackIndex++ % copy.happy.length];
    happyUntil = now + 1200;
    if (!automatic) {
      feedback.textContent = `${gauge.action}，${gauge.label}已补充至 ${Math.round(gauge.value)}%。`;
      requestTick();
    }
    draw(gauge);
  }

  function animate(now) {
    frame = 0;
    // Freeze time when paused/hidden. Cap a stalled frame to avoid catch-up bursts.
    const elapsed = Math.max(0, Math.min(100, now - lastFrame));
    lastFrame = now;
    if (playing) {
      demoTime += elapsed;
      for (const gauge of gauges) {
        gauge.value = Math.max(0, gauge.value - elapsed / 1000 * speed * 100 / (gauge.minutes * 60));
        if (demoTime >= gauge.nextHit) {
          replenish(gauge, true);
          gauge.impactStart = reducedMotion.matches ? null : now;
          gauge.nextHit += gauge.period;
        }
      }
      if (demoTime >= nextUpdate) {
        for (const gauge of gauges) {
          // Let a refill finish before publishing the next decay snapshot.
          if (!gauge.continuous && !gauge.infusion) {
            gauge.displayed = gauge.value;
            gauge.shown = gauge.displayed / 10;
          }
        }
        nextUpdate += (Math.floor((demoTime - nextUpdate) / updateInterval) + 1) * updateInterval;
      }
      positionNotes();
    }
    let active = false;
    for (const gauge of gauges) {
      if (gauge.continuous) {
        gauge.displayed = gauge.value;
        if (!gauge.infusion) gauge.shown = gauge.displayed / 10;
      }
      if (gauge.impactStart !== null) {
        const t = Math.max(0, Math.min(1, (now - gauge.impactStart) / 320));
        gauge.impact.style.opacity = (1 - t) ** 2;
        gauge.impact.style.transform = `translate(-50%, -50%) scale(${.35 + easeOut(t) * .8})`;
        if (t >= 1) gauge.impactStart = null;
      }
      if (gauge.infusion) {
        const job = gauge.infusion;
        const t = Math.max(0, Math.min(1, (now - job.start) / job.duration));
        // Water keeps decaying during a refill, so its finish has no downward jump.
        gauge.shown = gauge.continuous
          ? gauge.displayed / 10 - (job.target - job.from) * (1 - easeOut(t))
          : job.from + (job.target - job.from) * easeOut(t);
        if (t >= 1) { gauge.infusion = null; gauge.shown = gauge.displayed / 10; }
      }
      if (gauge.paddle) {
        const t = Math.max(0, Math.min(1, (now - gauge.paddle.start) / 440));
        if (t >= 1) {
          gauge.travel = 0;
          gauge.paddle = null;
        } else {
          const stops = [[0, gauge.paddle.from], [0.2, 6], [0.3, 6], [0.7, -1], [0.85, 0.5], [1, 0]];
          const index = stops.findIndex(stop => stop[0] > t);
          const [t0, from] = stops[index - 1], [t1, to] = stops[index];
          gauge.travel = from + (to - from) * easeOut((t - t0) / (t1 - t0));
        }
      }
      draw(gauge);
      active ||= Boolean(gauge.infusion || gauge.paddle || gauge.impactStart !== null);
    }
    updateMessage(now);
    if (playing || active || now < happyUntil) frame = requestAnimationFrame(animate);
  }

  function settleAnimations() {
    for (const gauge of gauges) {
      gauge.shown = gauge.displayed / 10;
      gauge.infusion = gauge.paddle = null;
      gauge.impactStart = null;
      gauge.impact.style.opacity = 0;
      gauge.travel = 0;
      draw(gauge);
    }
  }

  function requestTick() {
    if (frame || document.hidden) return;
    lastFrame = performance.now();
    frame = requestAnimationFrame(animate);
  }

  function positionNotes() {
    for (const gauge of gauges) {
      if (!gauge.geometry) continue;
      const remaining = gauge.nextHit - demoTime;
      const visible = remaining > 0 && remaining <= flightDuration;
      gauge.note.style.display = visible ? "" : "none";
      if (!visible) continue;
      const t = 1 - remaining / flightDuration;
      const { x, y, startX, startY, size } = gauge.geometry;
      const left = startX + (x - startX) * t - size / 2;
      const top = startY + (y - startY) * t - size / 2;
      gauge.note.style.transform = `translate3d(${left}px, ${top}px, 0)`;
      gauge.note.style.opacity = Math.min(1, t / .12);
    }
  }

  function measureLanes() {
    const bounds = stage.getBoundingClientRect();
    const device = document.querySelector(".device").getBoundingClientRect();
    const size = Math.max(20, Math.min(32, device.width * 16 / 205));
    const vertical = matchMedia("(max-width: 600px)").matches;
    for (const [index, gauge] of gauges.entries()) {
      const button = gauge.row.querySelector("button").getBoundingClientRect();
      const edgeX = vertical ? device.left - bounds.left + device.width * (index + 1) / 4 : device.right - bounds.left;
      const edgeY = vertical ? device.top - bounds.top : button.top + button.height / 2 - bounds.top;
      // The visible leading pixel touches the casing, without entering it.
      const x = vertical ? edgeX : edgeX + size * (.5 - gauge.symbol.x / 16);
      const y = vertical ? edgeY + size * (.5 - (gauge.symbol.y + gauge.symbol.height) / 16) : edgeY;
      gauge.geometry = { x, y, startX: vertical ? x : bounds.width - size / 2, startY: vertical ? size / 2 : y, size };
      Object.assign(gauge.lane.style, {
        left: `${edgeX}px`, top: vertical ? "0" : `${edgeY}px`,
        width: vertical ? "1px" : `${bounds.width - edgeX}px`, height: vertical ? `${edgeY}px` : "1px",
      });
      Object.assign(gauge.impact.style, { left: `${edgeX}px`, top: `${edgeY}px` });
      Object.assign(gauge.note.style, { width: `${size}px`, height: `${size}px` });
    }
    positionNotes();
  }

  function updatePlayback() {
    playback.classList.toggle("is-paused", !playing);
    const label = playing ? "暂停自动演示" : "播放自动演示";
    playback.setAttribute("aria-label", label);
    playback.title = label;
    requestTick();
  }

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      if (frame) cancelAnimationFrame(frame);
      frame = 0;
      settleAnimations();
    } else requestTick();
  });
  playback.addEventListener("click", () => {
    playing = !playing;
    updatePlayback();
  });
  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) {
      playing = false;
      settleAnimations();
      updatePlayback();
    }
  });
  new ResizeObserver(measureLanes).observe(stage);
  measureLanes();
  playback.hidden = false;
  updatePlayback();
  gauges.forEach(draw);
})();
