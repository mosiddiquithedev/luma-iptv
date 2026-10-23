const tabs = [...document.querySelectorAll("[data-platform]")];
function selectTab(tab) {
  for (const t of tabs) {
    const chosen = t === tab;
    t.setAttribute("aria-selected", String(chosen));
    t.tabIndex = chosen ? 0 : -1;
    document.getElementById("gallery-" + t.dataset.platform).hidden = !chosen;
  }
}
for (const tab of tabs) {
  tab.addEventListener("click", () => selectTab(tab));
  tab.addEventListener("keydown", (e) => {
    if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) {
      e.preventDefault();
      let index =
        e.key === "Home"
          ? 0
          : e.key === "End"
            ? tabs.length - 1
            : (tabs.indexOf(tab) +
                (e.key === "ArrowRight" ? 1 : -1) +
                tabs.length) %
              tabs.length;
      selectTab(tabs[index]);
      tabs[index].focus();
    }
  });
}
const lightbox = document.getElementById("lightbox");
for (const button of document.querySelectorAll("[data-image]"))
  button.addEventListener("click", () => {
    lightbox.querySelector("img").src = button.dataset.image;
    lightbox.querySelector("img").alt = button.querySelector("img").alt;
    lightbox.querySelector("p").textContent = button.dataset.caption;
    lightbox.showModal();
  });
lightbox
  .querySelector(".close")
  .addEventListener("click", () => lightbox.close());
lightbox.addEventListener("click", (e) => {
  if (e.target === lightbox) {
    const rect = lightbox.getBoundingClientRect();
    if (
      e.clientX < rect.left ||
      e.clientX > rect.right ||
      e.clientY < rect.top ||
      e.clientY > rect.bottom
    )
      lightbox.close();
  }
});
