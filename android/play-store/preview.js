const { panels, panelWidth } = window.PLAY_STORE_CONFIG;
const params = new URLSearchParams(window.location.search);
document.documentElement.dataset.export = params.get("export") === "1" ? "true" : "false";

const panelRoot = document.querySelector("#panels");
const deviceRoot = document.querySelector("#devices");
const guideRoot = document.querySelector("#guides");

for (const [index, panel] of panels.entries()) {
  const article = document.createElement("article");
  article.className = "panel";
  article.dataset.accent = panel.accent;
  article.innerHTML = `
    <span class="panel__number">${panel.number}</span>
    <p class="panel__kicker">${panel.kicker}</p>
    <h1 class="panel__title">${panel.title}</h1>
    <p class="panel__body">${panel.body}</p>
  `;
  panelRoot.append(article);

  const device = document.createElement("div");
  device.className = "device";
  device.dataset.theme = panel.accent;
  device.dataset.repairStatus = panel.repairDarkStatusBar ? "true" : "false";
  device.style.left = `${panel.device.left}px`;
  device.style.top = `${panel.device.top}px`;
  device.style.setProperty("--device-width", `${panel.device.width}px`);
  device.style.setProperty("--device-rotate", `${panel.device.rotate}deg`);
  device.innerHTML = `
    <i class="device__button device__button--power"></i>
    <i class="device__button device__button--volume"></i>
    <div class="device__screen">
      <img class="device__shot" src="${panel.image}" alt="" />
      <div class="status-repair"><span>10:00</span><span class="status-repair__icons"><i class="wifi"></i><i class="battery"></i></span></div>
      <span class="device__glass"></span>
    </div>
  `;
  deviceRoot.append(device);

  if (index > 0) {
    const guide = document.createElement("span");
    guide.className = "guide";
    guide.dataset.label = `cut ${index + 1}`;
    guide.style.left = `${index * panelWidth}px`;
    guideRoot.append(guide);
  }
}

Promise.all([...document.images].map((image) => image.decode().catch(() => {})))
  .then(() => document.fonts.ready)
  .then(() => { document.documentElement.dataset.ready = "true"; });
