import { createApp } from "vue";
import App from "./App.vue";
import { installMobileGuards } from "./core/guards";
import { initSettings } from "./store/useSettings";
import "./styles/global.css";

/*
 * 外观设置（主题 / 壁纸 / 字号）要在挂载前应用，避免首屏闪一下再变色。
 */
initSettings();

/*
 * iOS 上没有右键菜单，但有长按菜单、双击缩放、橡皮筋滚动这些「网页感」的行为，
 * 逐个拦掉，让手感更接近原生 App。
 */
installMobileGuards();

createApp(App).mount("#app");
