import { createApp } from "vue";
import App from "./App.vue";
import { installDesktopGuards } from "./core/desktopGuards";
import "./styles/global.css";

// 桌面程序里屏蔽右键菜单、刷新、打印、另存为等浏览器行为；
// 开发时保留开发者工具，方便调试。
installDesktopGuards({ allowDevTools: import.meta.env.DEV });

createApp(App).mount("#app");
