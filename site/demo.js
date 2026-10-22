(() => {
  "use strict";

  // Standalone browser demo. No storage, analytics, fonts, or network requests.
  // The app's 45 / 180 / 20 minute cycles are shown at 20× speed here.
  const speed = 20;
  const updateInterval = 5 * 60 * 1000 / speed;
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
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
    hp: { value: 70, minutes: 45, action: "起身走一走", label: "HP" },
    water: { value: 30, minutes: 180, action: "喝一杯水", label: "水分" },
    san: { value: 50, minutes: 20, action: "远眺一会儿", label: "SAN" },
  };
  const gauges = Object.entries(settings).map(([id, config]) => {
    const row = document.querySelector(`[data-gauge="${id}"]`);
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
    const gauge = { ...config, id, row, meter, cells, displayed: config.value, shown: config.value / 10, infusion: null, paddle: null, travel: 0 };
    row.querySelector("button").addEventListener("click", () => replenish(gauge));
    return gauge;
  });
  pixels(document.querySelector(".streak svg"), patterns.flame, true);

  let frame = 0;
  let happyUntil = 0;
  let feedbackIndex = 0;
  let lastTick = performance.now();
  let nextUpdate = lastTick + updateInterval;
  let pausedAt = 0;
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

  function replenish(gauge) {
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
      if (!frame) frame = requestAnimationFrame(animate);
    }
    message.textContent = copy.happy[feedbackIndex++ % copy.happy.length];
    happyUntil = now + 1200;
    feedback.textContent = `${gauge.action}，${gauge.label}已补充至 ${Math.round(gauge.value)}%。`;
    draw(gauge);
  }

  function animate(now) {
    frame = 0;
    let active = false;
    for (const gauge of gauges) {
      if (gauge.infusion) {
        const job = gauge.infusion;
        const t = Math.max(0, Math.min(1, (now - job.start) / job.duration));
        gauge.shown = job.from + (job.target - job.from) * easeOut(t);
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
      active ||= Boolean(gauge.infusion || gauge.paddle);
    }
    if (active) frame = requestAnimationFrame(animate);
  }

  function settleAnimations() {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    for (const gauge of gauges) {
      gauge.shown = gauge.displayed / 10;
      gauge.infusion = gauge.paddle = null;
      gauge.travel = 0;
      draw(gauge);
    }
  }

  setInterval(() => {
    const now = performance.now();
    const elapsed = (now - lastTick) / 1000;
    lastTick = now;
    if (document.hidden) return;
    for (const gauge of gauges) {
      gauge.value = Math.max(0, gauge.value - elapsed * speed * 100 / (gauge.minutes * 60));
    }
    if (now >= nextUpdate) {
      for (const gauge of gauges) {
        gauge.displayed = gauge.value;
        if (!gauge.infusion) gauge.shown = gauge.displayed / 10;
        draw(gauge);
      }
      nextUpdate += (Math.floor((now - nextUpdate) / updateInterval) + 1) * updateInterval;
    }
    updateMessage(now);
  }, 250);

  document.addEventListener("visibilitychange", () => {
    lastTick = performance.now();
    if (document.hidden) {
      pausedAt = lastTick;
      settleAnimations();
    } else if (pausedAt) {
      nextUpdate += lastTick - pausedAt;
      pausedAt = 0;
    }
  });
  reducedMotion.addEventListener("change", () => {
    if (reducedMotion.matches) settleAnimations();
  });
  gauges.forEach(draw);
})();
