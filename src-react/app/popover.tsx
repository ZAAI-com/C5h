import React from "react";
import ReactDOM from "react-dom/client";
import { PopoverWindow } from "@/features/windows/PopoverWindow";
import "@/styles/index.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <PopoverWindow />
  </React.StrictMode>,
);
