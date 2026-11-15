import { createApp } from "vue";
import App from "./App.vue";
import { installDesktopGuards } from "./core/desktopGuards";
import { initSettings } from "./store/useSettings";
import "./styles/global.css";

// 桌面程序里屏蔽右键菜单、刷新、打印、另存为等浏览器行为；
// 开发时保留开发者工具，方便调试。
installDesktopGuards({ allowDevTools: import.meta.env.DEV });

// 外观设置（主题 / 壁纸 / 字号）要在挂载前应用，避免首屏闪一下再变色
initSettings();

createApp(App).mount("#app");
