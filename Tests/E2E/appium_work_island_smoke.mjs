const baseURL = process.env.APPIUM_URL ?? "http://127.0.0.1:4724/wd/hub";
const appBundleID = "dev.kanyun.CodexHermesTouchBar";
let sessionID;
let passed = 0;

function assert(condition, message) {
  if (!condition) throw new Error(message);
  passed += 1;
  process.stdout.write(`PASS ${passed}: ${message}\n`);
}

async function request(path, method = "GET", body) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: body ? { "content-type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const result = await response.json();
  if (!response.ok || result.value?.error) {
    throw new Error(`${method} ${path}: ${JSON.stringify(result.value ?? result)}`);
  }
  return result.value;
}

async function source() {
  return request(`/session/${sessionID}/source`);
}

async function waitForSource(predicate, timeoutMilliseconds = 4_000) {
  const deadline = Date.now() + timeoutMilliseconds;
  let tree = await source();
  while (!predicate(tree) && Date.now() < deadline) {
    await delay(400);
    tree = await source();
  }
  return tree;
}

async function find(using, value) {
  const element = await request(`/session/${sessionID}/element`, "POST", { using, value });
  return element["element-6066-11e4-a52e-4f735466cecf"] ?? element.ELEMENT;
}

async function click(elementID) {
  await request(`/session/${sessionID}/element/${elementID}/click`, "POST", {});
}

async function movePointerOutside() {
  await movePointer(100, 900);
}

async function movePointer(x, y) {
  await request(`/session/${sessionID}/actions`, "POST", {
    actions: [{
      type: "pointer",
      id: "smoke-mouse",
      parameters: { pointerType: "mouse" },
      actions: [{ type: "pointerMove", duration: 100, x, y, origin: "viewport" }],
    }],
  });
}

function capsuleCenter(tree) {
  const match = tree.match(
    /XCUIElementTypeButton[^>]*label="恢复 AI 工作岛[^>]*x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"/
  );
  if (!match) throw new Error("Could not resolve floating capsule frame");
  return {
    x: Number(match[1]) + Number(match[3]) / 2,
    y: Number(match[2]) + Number(match[4]) / 2,
  };
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

try {
  const session = await request("/session", "POST", {
    capabilities: {
      alwaysMatch: {
        platformName: "Mac",
        "appium:automationName": "Mac2",
        "appium:bundleId": appBundleID,
        "appium:newCommandTimeout": 120,
      },
    },
  });
  sessionID = session.sessionId;
  assert(session.capabilities.bundleId === appBundleID, "会话绑定到 AI 工作岛 Bundle ID");

  let tree = await source();
  if (!tree.includes("恢复 AI 工作岛") && tree.includes("新任务指令")) {
    await movePointerOutside();
    await delay(900);
    tree = await source();
  }
  assert(tree.includes("恢复 AI 工作岛"), "冷启动可读取悬浮胶囊");

  let center = capsuleCenter(tree);
  await movePointer(center.x, center.y);
  await delay(250);
  tree = await waitForSource(
    (value) => value.includes("额度剩余") || value.includes("公司额度")
  );
  assert(tree.includes("新任务指令"), "指向胶囊后真实面板展开");
  assert(tree.includes("创建新任务"), "展开面板包含新任务发送入口");
  assert(
    tree.includes("额度剩余") || tree.includes("公司额度"),
    "展开面板包含额度摘要"
  );

  const prompt = await find("accessibility id", "新任务指令");
  const marker = "Appium UI smoke input";
  await request(`/session/${sessionID}/element/${prompt}/value`, "POST", {
    text: marker,
    value: [...marker],
  });
  tree = await source();
  assert(tree.includes(marker), "新任务输入框可写入但不提交");
  await request(`/session/${sessionID}/element/${prompt}/clear`, "POST", {});
  tree = await source();
  assert(!tree.includes(marker), "冒烟测试临时输入已清理");

  await movePointerOutside();
  await delay(900);
  tree = await source();
  assert(!tree.includes("新任务指令") && tree.includes("恢复 AI 工作岛"), "鼠标离开后面板自动回缩");

  for (let index = 0; index < 3; index += 1) {
    tree = await source();
    center = capsuleCenter(tree);
    await movePointer(center.x, center.y);
    await delay(120);
    await movePointerOutside();
    await delay(800);
  }
  tree = await source();
  assert(tree.includes("恢复 AI 工作岛") && !tree.includes("新任务指令"), "快速展开回缩三轮后窗口未消失或卡死");

  const screenshot = await request(`/session/${sessionID}/screenshot`);
  assert(typeof screenshot === "string" && screenshot.length > 1_000, "安装版截图可由黑盒驱动真实回读");
  process.stdout.write(`Appium smoke passed: ${passed} assertions\n`);
} finally {
  if (sessionID) {
    await request(`/session/${sessionID}`, "DELETE").catch(() => {});
  }
}
