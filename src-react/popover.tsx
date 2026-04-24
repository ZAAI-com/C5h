import React from "react";
import ReactDOM from "react-dom/client";
import { PopoverWindow } from "./components/PopoverWindow";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <PopoverWindow />
  </React.StrictMode>,
);
