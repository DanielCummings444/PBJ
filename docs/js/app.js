/* ──────────────────────────────────────────────
   PBJ PBIP Analyzer — GitHub Pages Upload Client
   ────────────────────────────────────────────── */

(function () {
  "use strict";

  // ── State ────────────────────────────────────
  let ghToken = "";
  let ghOwner = "";
  let ghRepo = "";
  let ghBranch = "";
  let selectedFiles = []; // { path, content (base64), size }

  // ── DOM refs ─────────────────────────────────
  const $ = (s) => document.querySelector(s);
  const setupPanel   = $("#setup-panel");
  const uploadPanel  = $("#upload-panel");
  const reportsPanel = $("#reports-panel");
  const logPanel     = $("#log-panel");

  // ── Init ─────────────────────────────────────
  function init() {
    // Restore saved config
    ghToken  = localStorage.getItem("pbj_token") || "";
    ghOwner  = localStorage.getItem("pbj_owner") || "";
    ghRepo   = localStorage.getItem("pbj_repo")  || "";
    ghBranch = localStorage.getItem("pbj_branch") || "main";

    $("#gh-token").value = ghToken;
    $("#gh-owner").value = ghOwner;
    $("#gh-repo").value  = ghRepo;
    $("#gh-branch").value = ghBranch;

    // Events
    $("#btn-connect").addEventListener("click", handleConnect);
    $("#file-input").addEventListener("change", handleFileSelect);
    $("#btn-upload").addEventListener("click", handleUpload);
    $("#btn-clear").addEventListener("click", clearFiles);
    $("#btn-refresh").addEventListener("click", loadReports);

    // Drag & drop
    const dz = $("#drop-zone");
    dz.addEventListener("dragover", (e) => { e.preventDefault(); dz.classList.add("dragover"); });
    dz.addEventListener("dragleave", () => dz.classList.remove("dragover"));
    dz.addEventListener("drop", handleDrop);
    dz.addEventListener("click", () => $("#file-input").click());

    // Auto-connect if we have saved creds
    if (ghToken && ghOwner && ghRepo) {
      handleConnect();
    }
  }

  // ── Connect ──────────────────────────────────
  async function handleConnect() {
    ghToken  = $("#gh-token").value.trim();
    ghOwner  = $("#gh-owner").value.trim();
    ghRepo   = $("#gh-repo").value.trim();
    ghBranch = $("#gh-branch").value.trim() || "main";

    if (!ghToken || !ghOwner || !ghRepo) {
      setStatus("connect-status", "Please fill in all fields.", "err");
      return;
    }

    setStatus("connect-status", "Connecting...", "");

    try {
      const res = await ghApi(`/repos/${ghOwner}/${ghRepo}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();

      // Save to localStorage
      localStorage.setItem("pbj_token", ghToken);
      localStorage.setItem("pbj_owner", ghOwner);
      localStorage.setItem("pbj_repo", ghRepo);
      localStorage.setItem("pbj_branch", ghBranch);

      setStatus("connect-status", `Connected to ${data.full_name}`, "ok");
      showApp();
      log("info", `Connected to ${data.full_name} (branch: ${ghBranch})`);
      loadReports();
    } catch (err) {
      setStatus("connect-status", `Connection failed: ${err.message}`, "err");
    }
  }

  function showApp() {
    uploadPanel.classList.remove("hidden");
    reportsPanel.classList.remove("hidden");
    logPanel.classList.remove("hidden");
  }

  // ── File Selection ───────────────────────────
  function handleFileSelect(e) {
    processFileList(e.target.files);
  }

  function handleDrop(e) {
    e.preventDefault();
    $("#drop-zone").classList.remove("dragover");

    if (e.dataTransfer.items) {
      const entries = [];
      for (const item of e.dataTransfer.items) {
        if (item.kind === "file") {
          const entry = item.webkitGetAsEntry ? item.webkitGetAsEntry() : null;
          if (entry) {
            entries.push(entry);
          }
        }
      }
      if (entries.length > 0) {
        readEntriesRecursive(entries);
        return;
      }
    }

    if (e.dataTransfer.files.length > 0) {
      processFileList(e.dataTransfer.files);
    }
  }

  function readEntriesRecursive(entries) {
    const files = [];
    let pending = 0;

    function readEntry(entry, path) {
      if (entry.isFile) {
        pending++;
        entry.file((file) => {
          file._relativePath = path + file.name;
          files.push(file);
          pending--;
          if (pending === 0) processFileList(files);
        });
      } else if (entry.isDirectory) {
        pending++;
        const reader = entry.createReader();
        reader.readEntries((childEntries) => {
          for (const child of childEntries) {
            readEntry(child, path + entry.name + "/");
          }
          pending--;
          if (pending === 0 && files.length > 0) processFileList(files);
        });
      }
    }

    for (const entry of entries) {
      readEntry(entry, "");
    }
  }

  async function processFileList(fileList) {
    selectedFiles = [];
    const arr = Array.from(fileList);

    for (const file of arr) {
      const path = file._relativePath || file.webkitRelativePath || file.name;
      // Skip hidden/cache files
      if (path.includes(".pbi/cache.abf") || path.includes("localSettings.json")) continue;
      if (path.startsWith(".")) continue;

      const content = await readFileBase64(file);
      selectedFiles.push({ path, content, size: file.size });
    }

    if (selectedFiles.length === 0) {
      return;
    }

    // Auto-detect project name from folder structure
    const firstPath = selectedFiles[0].path;
    const parts = firstPath.split("/");
    let projectName = parts.length > 1 ? parts[0] : "MyProject";
    // Clean up common suffixes
    projectName = projectName.replace(/\.(pbip|Report|SemanticModel|Dataset)$/i, "");
    if (!projectName) projectName = "MyProject";
    $("#project-name").value = projectName;

    renderFileList();
  }

  function readFileBase64(file) {
    return new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => {
        const base64 = reader.result.split(",")[1] || "";
        resolve(base64);
      };
      reader.readAsDataURL(file);
    });
  }

  function renderFileList() {
    const list = $("#file-list");
    list.innerHTML = "";
    for (const f of selectedFiles) {
      const div = document.createElement("div");
      div.className = "file-entry";
      div.innerHTML = `${escapeHtml(f.path)} <span class="size">${formatSize(f.size)}</span>`;
      list.appendChild(div);
    }
    $("#file-preview").classList.remove("hidden");
  }

  function clearFiles() {
    selectedFiles = [];
    $("#file-list").innerHTML = "";
    $("#file-preview").classList.add("hidden");
    $("#file-input").value = "";
  }

  // ── Upload ───────────────────────────────────
  async function handleUpload() {
    if (selectedFiles.length === 0) return;

    const projectName = $("#project-name").value.trim() || "MyProject";
    const btn = $("#btn-upload");
    btn.disabled = true;

    const progressArea = $("#upload-progress");
    const progressFill = $("#progress-fill");
    const progressText = $("#progress-text");
    progressArea.classList.remove("hidden");

    log("info", `Starting upload of ${selectedFiles.length} files for project "${projectName}"...`);

    try {
      // Get the latest commit SHA for the branch to build a tree
      const refRes = await ghApi(`/repos/${ghOwner}/${ghRepo}/git/ref/heads/${ghBranch}`);
      if (!refRes.ok) {
        throw new Error(`Branch "${ghBranch}" not found (${refRes.status}). Push at least one commit first.`);
      }
      const refData = await refRes.json();
      const latestCommitSha = refData.object.sha;

      // Get the tree SHA of the latest commit
      const commitRes = await ghApi(`/repos/${ghOwner}/${ghRepo}/git/commits/${latestCommitSha}`);
      const commitData = await commitRes.json();
      const baseTreeSha = commitData.tree.sha;

      // Create blobs for each file
      const treeItems = [];
      for (let i = 0; i < selectedFiles.length; i++) {
        const file = selectedFiles[i];
        const pct = Math.round(((i + 1) / selectedFiles.length) * 70);
        progressFill.style.width = pct + "%";
        progressText.textContent = `Creating blob ${i + 1}/${selectedFiles.length}: ${file.path}`;

        const blobRes = await ghApi(`/repos/${ghOwner}/${ghRepo}/git/blobs`, {
          method: "POST",
          body: JSON.stringify({ content: file.content, encoding: "base64" }),
        });
        if (!blobRes.ok) throw new Error(`Failed to create blob for ${file.path}`);
        const blobData = await blobRes.json();

        treeItems.push({
          path: `sandbox/projects/${projectName}/${file.path}`,
          mode: "100644",
          type: "blob",
          sha: blobData.sha,
        });
      }

      // Create tree
      progressFill.style.width = "80%";
      progressText.textContent = "Creating commit tree...";

      const treeRes = await ghApi(`/repos/${ghOwner}/${ghRepo}/git/trees`, {
        method: "POST",
        body: JSON.stringify({ base_tree: baseTreeSha, tree: treeItems }),
      });
      if (!treeRes.ok) throw new Error("Failed to create tree");
      const treeData = await treeRes.json();

      // Create commit
      progressFill.style.width = "90%";
      progressText.textContent = "Creating commit...";

      const commitMsg = `Upload PBIP project: ${projectName}\n\nUploaded ${selectedFiles.length} files via PBJ web interface.`;
      const newCommitRes = await ghApi(`/repos/${ghOwner}/${ghRepo}/git/commits`, {
        method: "POST",
        body: JSON.stringify({
          message: commitMsg,
          tree: treeData.sha,
          parents: [latestCommitSha],
        }),
      });
      if (!newCommitRes.ok) throw new Error("Failed to create commit");
      const newCommitData = await newCommitRes.json();

      // Update branch ref
      progressFill.style.width = "95%";
      progressText.textContent = "Updating branch...";

      const updateRes = await ghApi(`/repos/${ghOwner}/${ghRepo}/git/refs/heads/${ghBranch}`, {
        method: "PATCH",
        body: JSON.stringify({ sha: newCommitData.sha }),
      });
      if (!updateRes.ok) throw new Error("Failed to update branch ref");

      progressFill.style.width = "100%";
      progressText.textContent = `Upload complete! ${selectedFiles.length} files committed.`;
      log("success", `Uploaded ${selectedFiles.length} files to sandbox/projects/${projectName}/`);
      log("info", "GitHub Actions workflow will now analyze the project and generate reports.");
      log("info", `Commit: ${newCommitData.sha.substring(0, 7)}`);

      clearFiles();

      // Poll for reports after a delay
      setTimeout(() => loadReports(), 5000);

    } catch (err) {
      progressText.textContent = `Error: ${err.message}`;
      progressFill.style.width = "0%";
      log("error", `Upload failed: ${err.message}`);
    } finally {
      btn.disabled = false;
    }
  }

  // ── Reports ──────────────────────────────────
  async function loadReports() {
    const list = $("#reports-list");
    list.innerHTML = '<p class="muted">Loading reports...</p>';

    try {
      // List files in sandbox/reports/
      const res = await ghApi(
        `/repos/${ghOwner}/${ghRepo}/contents/sandbox/reports?ref=${ghBranch}`
      );

      if (res.status === 404) {
        list.innerHTML = '<p class="muted">No reports yet. Upload a PBIP project to get started.</p>';
        return;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      const files = await res.json();
      const reportFiles = files.filter(
        (f) => f.type === "file" && (f.name.endsWith(".md") || f.name.endsWith(".json"))
      );

      if (reportFiles.length === 0) {
        list.innerHTML = '<p class="muted">No reports yet. Upload a PBIP project to get started.</p>';
        return;
      }

      list.innerHTML = "";
      for (const file of reportFiles) {
        const card = document.createElement("div");
        card.className = "report-card";

        const isMarkdown = file.name.endsWith(".md");
        const icon = isMarkdown ? "Whitepaper" : "JSON Data";
        const sizeStr = formatSize(file.size);

        card.innerHTML = `
          <div class="report-info">
            <h4>${escapeHtml(file.name)}</h4>
            <p>${icon} &middot; ${sizeStr}</p>
          </div>
          <div class="report-actions">
            <button class="btn secondary btn-view" data-url="${file.download_url}" data-name="${file.name}">View</button>
            <button class="btn primary btn-download" data-url="${file.download_url}" data-name="${file.name}">Download</button>
          </div>
        `;
        list.appendChild(card);
      }

      // Attach download/view handlers
      list.querySelectorAll(".btn-download").forEach((btn) => {
        btn.addEventListener("click", () => downloadFile(btn.dataset.url, btn.dataset.name));
      });
      list.querySelectorAll(".btn-view").forEach((btn) => {
        btn.addEventListener("click", () => viewFile(btn.dataset.url, btn.dataset.name));
      });

      log("info", `Loaded ${reportFiles.length} report(s).`);
    } catch (err) {
      list.innerHTML = `<p class="muted">Failed to load reports: ${err.message}</p>`;
      log("error", `Failed to load reports: ${err.message}`);
    }
  }

  async function downloadFile(url, name) {
    try {
      const res = await fetch(url);
      const blob = await res.blob();
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = name;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(a.href);
      log("info", `Downloaded: ${name}`);
    } catch (err) {
      log("error", `Download failed: ${err.message}`);
    }
  }

  async function viewFile(url, name) {
    try {
      const res = await fetch(url);
      const text = await res.text();
      const win = window.open("", "_blank");
      if (name.endsWith(".md")) {
        win.document.write(`
          <html><head><title>${escapeHtml(name)}</title>
          <style>
            body { font-family: system-ui, sans-serif; max-width: 900px; margin: 40px auto; padding: 0 20px;
                   background: #0d1117; color: #c9d1d9; line-height: 1.7; }
            pre { background: #161b22; padding: 16px; border-radius: 8px; overflow-x: auto; }
            code { font-family: 'Consolas', monospace; }
            table { border-collapse: collapse; width: 100%; margin: 16px 0; }
            th, td { border: 1px solid #30363d; padding: 8px 12px; text-align: left; }
            th { background: #161b22; }
            h1, h2, h3, h4 { margin-top: 24px; }
            hr { border: none; border-top: 1px solid #30363d; margin: 24px 0; }
          </style></head><body><pre>${escapeHtml(text)}</pre></body></html>
        `);
      } else {
        win.document.write(`
          <html><head><title>${escapeHtml(name)}</title>
          <style>
            body { font-family: 'Consolas', monospace; background: #0d1117; color: #c9d1d9;
                   padding: 20px; white-space: pre-wrap; }
          </style></head><body>${escapeHtml(text)}</body></html>
        `);
      }
    } catch (err) {
      log("error", `View failed: ${err.message}`);
    }
  }

  // ── GitHub API Helper ────────────────────────
  function ghApi(path, options = {}) {
    const url = path.startsWith("http") ? path : `https://api.github.com${path}`;
    return fetch(url, {
      ...options,
      headers: {
        Authorization: `Bearer ${ghToken}`,
        Accept: "application/vnd.github+json",
        "Content-Type": "application/json",
        ...(options.headers || {}),
      },
    });
  }

  // ── Utilities ────────────────────────────────
  function setStatus(id, msg, cls) {
    const el = $(`#${id}`);
    el.textContent = msg;
    el.className = "status " + (cls || "");
  }

  function log(level, msg) {
    logPanel.classList.remove("hidden");
    const logEl = $("#activity-log");
    const entry = document.createElement("div");
    entry.className = `log-entry ${level}`;
    const ts = new Date().toLocaleTimeString();
    entry.innerHTML = `<span class="timestamp">${ts}</span>${escapeHtml(msg)}`;
    logEl.prepend(entry);
  }

  function escapeHtml(s) {
    const d = document.createElement("div");
    d.textContent = s;
    return d.innerHTML;
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + " B";
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
    return (bytes / (1024 * 1024)).toFixed(1) + " MB";
  }

  // ── Boot ─────────────────────────────────────
  document.addEventListener("DOMContentLoaded", init);
})();
