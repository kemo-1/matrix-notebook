const channel = new BroadcastChannel("taps_channel");
let isDuplicate = false;

channel.onmessage = (event) => {
  if (event.data === "ping") {
    channel.postMessage("pong");
  } else if (event.data === "pong") {
    isDuplicate = true;
  }
};

channel.postMessage("ping");

setTimeout(() => {
  if (!isDuplicate) {
    //@ts-ignore
    import("./src/notion_clone.gleam").then(({ main }) => {
      main({});
    });
  } else {
    document.body.innerHTML = `
      <div style="display:flex;justify-content:center;align-items:center;height:100vh;font-family:system-ui">
        <div style="text-align:center;padding:2rem;background:white;border-radius:8px;box-shadow:0 4px 12px rgba(0,0,0,0.1)">
          <h2 style="color:#dc3545">⚠️ Matrix Notebook Is Already Running</h2>
          <p style="color:#666">Close the other tab first</p>
          <button onclick="location.reload()" style="background:#007bff;color:white;border:none;padding:8px 16px;border-radius:4px;cursor:pointer">Refresh this page</button>
        </div>
      </div>`;
    console.log("Another tab is already open.");
  }
}, 300);

// import {
//   draggable,
//   dropTargetForElements,
// } from "@atlaskit/pragmatic-drag-and-drop/element/adapter";

// import * as Y from "yjs";
// import { YTree, checkForYTree } from "yjs-orderedtree";
// import { YTree as Ytree } from "./node_modules/yjs-orderedtree/dist/types/ytree";

// interface TreeNode {
//   name: string;
//   type: "file" | "folder";
//   children?: string[];
// }

// interface DragData {
//   nodeId: string;
//   parentId: string;
//   type: "file" | "folder";
// }

// let draggedNodeId: string | null = null;

// function createDropIndicator(): HTMLElement {
//   const indicator = document.createElement("div");
//   indicator.className = "drop-indicator hidden";
//   indicator.style.cssText = `
//     height: 2px;
//     background-color: #60a5fa;
//     border-radius: 1px;
//     transition: all 0.2s ease;
//     margin: 2px 0;
//     opacity: 0;
//   `;
//   return indicator;
// }

// function isDescendant(
//   yTree: Ytree,
//   ancestorId: string,
//   nodeId: string
// ): boolean {
//   const children = yTree.getNodeChildrenFromKey(ancestorId);
//   for (const childId of children) {
//     if (childId === nodeId || isDescendant(yTree, childId, nodeId)) {
//       return true;
//     }
//   }
//   return false;
// }

// function setupDropIndicator(
//   indicator: HTMLElement,
//   yTree: Ytree,
//   nodeId: string,
//   parentId: string,
//   rerenderCallback: () => void
// ): void {
//   dropTargetForElements({
//     element: indicator,
//     canDrop: ({ source }) => {
//       const data = source.data as DragData;
//       const sourceNodeId = data.nodeId;
//       const sourceParentId = data.parentId;

//       // Allow reordering within the same parent
//       return sourceParentId === parentId && sourceNodeId !== nodeId;
//     },
//     onDragEnter: () => {
//       indicator.style.opacity = "1";
//       indicator.style.height = "2px";
//       indicator.style.margin = "2px 0";
//     },
//     onDragLeave: () => {
//       indicator.style.opacity = "0";
//       indicator.style.height = "0px";
//       indicator.style.margin = "0";
//     },
//     onDrop: ({ source }) => {
//       indicator.style.opacity = "0";
//       indicator.style.height = "0px";
//       indicator.style.margin = "0";

//       const data = source.data as DragData;
//       const sourceNodeId = data.nodeId;

//       if (sourceNodeId && sourceNodeId !== nodeId) {
//         yTree.moveChildToParent(sourceNodeId, parentId);
//         rerenderCallback();
//       }
//     },
//   });
// }

// function setupFolderDropTarget(
//   element: HTMLElement,
//   yTree: Ytree,
//   nodeId: string,
//   rerenderCallback: () => void
// ): void {
//   dropTargetForElements({
//     element,
//     canDrop: ({ source }) => {
//       const data = source.data as DragData;
//       const sourceNodeId = data.nodeId;
//       // Prevent dropping on self or child nodes
//       return (
//         sourceNodeId !== nodeId && !isDescendant(yTree, sourceNodeId, nodeId)
//       );
//     },
//     onDragEnter: () => {
//       element.classList.add("drop-target");
//       element.style.backgroundColor = "#1e40af";
//       element.style.transform = "scale(1.02)";
//       element.style.border = "2px dashed #60a5fa";
//     },
//     onDragLeave: () => {
//       element.classList.remove("drop-target");
//       element.style.backgroundColor = "transparent";
//       element.style.transform = "scale(1)";
//       element.style.border = "none";
//     },
//     onDrop: ({ source }) => {
//       element.classList.remove("drop-target");
//       element.style.backgroundColor = "transparent";
//       element.style.transform = "scale(1)";
//       element.style.border = "none";

//       const data = source.data as DragData;
//       const sourceNodeId = data.nodeId;

//       if (sourceNodeId && sourceNodeId !== nodeId) {
//         yTree.moveChildToParent(sourceNodeId, nodeId);
//         rerenderCallback();
//       }
//     },
//   });
// }

// function setupFinalDropIndicator(
//   indicator: HTMLElement,
//   yTree: Ytree,
//   folderId: string,
//   rerenderCallback: () => void
// ): void {
//   dropTargetForElements({
//     element: indicator,
//     canDrop: ({ source }) => {
//       const data = source.data as DragData;
//       const sourceNodeId = data.nodeId;
//       const sourceParentId = data.parentId;

//       // Allow dropping at the end of this folder
//       return (
//         sourceParentId !== folderId &&
//         sourceNodeId !== folderId &&
//         !isDescendant(yTree, sourceNodeId, folderId)
//       );
//     },
//     onDragEnter: () => {
//       indicator.style.opacity = "1";
//       indicator.style.height = "2px";
//       indicator.style.margin = "2px 0";
//     },
//     onDragLeave: () => {
//       indicator.style.opacity = "0";
//       indicator.style.height = "0px";
//       indicator.style.margin = "0";
//     },
//     onDrop: ({ source }) => {
//       indicator.style.opacity = "0";
//       indicator.style.height = "0px";
//       indicator.style.margin = "0";

//       const data = source.data as DragData;
//       const sourceNodeId = data.nodeId;

//       if (sourceNodeId && sourceNodeId !== folderId) {
//         yTree.moveChildToParent(sourceNodeId, folderId);
//         rerenderCallback();
//       }
//     },
//   });
// }

// function renderTreeStyled(
//   yTree: Ytree,
//   nodeId: string,
//   container: HTMLElement,
//   indent: number = 0,
//   parentId: string = "root",
//   rerenderCallback: () => void
// ): void {
//   const node = yTree.getNodeValueFromKey(nodeId) as TreeNode;
//   if (!node) return;

//   const icon = node.type === "folder" ? "📁" : "📄";

//   // Create drop indicator for positioning
//   const dropIndicator = createDropIndicator();
//   container.appendChild(dropIndicator);
//   setupDropIndicator(dropIndicator, yTree, nodeId, parentId, rerenderCallback);

//   // Create tree node element
//   const nodeElement = document.createElement("div");
//   nodeElement.className = "tree-node";
//   nodeElement.dataset.nodeId = nodeId;
//   nodeElement.dataset.parentId = parentId;
//   nodeElement.style.cssText = `
//     padding-left: ${indent * 20}px;
//     font-family: 'Courier New', monospace;
//     line-height: 1.6;
//     padding-top: 4px;
//     padding-bottom: 4px;
//     padding-right: 8px;
//     border-radius: 4px;
//     transition: all 0.2s ease;
//     margin: 1px 0;
//     user-select: none;
//     cursor: grab;
//     position: relative;
//   `;

//   // Add hover effect
//   nodeElement.addEventListener("mouseenter", () => {
//     if (
//       !nodeElement.classList.contains("dragging") &&
//       !nodeElement.classList.contains("drop-target")
//     ) {
//       nodeElement.style.backgroundColor = "#031c27";
//     }
//   });

//   nodeElement.addEventListener("mouseleave", () => {
//     if (!nodeElement.classList.contains("drop-target")) {
//       nodeElement.style.backgroundColor = "transparent";
//     }
//   });

//   nodeElement.textContent = `${icon} ${node.name}`;
//   container.appendChild(nodeElement);

//   // Make the element draggable
//   draggable({
//     element: nodeElement,
//     onDragStart: () => {
//       draggedNodeId = nodeId;
//       nodeElement.classList.add("dragging");
//       nodeElement.style.opacity = "0.5";
//       nodeElement.style.cursor = "grabbing";
//     },
//     onDrop: () => {
//       nodeElement.classList.remove("dragging");
//       nodeElement.style.opacity = "1";
//       nodeElement.style.cursor = "grab";
//       draggedNodeId = null;
//     },
//     getInitialData: (): DragData => ({
//       nodeId,
//       parentId,
//       type: node.type,
//     }),
//   });

//   // Make folders drop targets
//   if (node.type === "folder") {
//     setupFolderDropTarget(nodeElement, yTree, nodeId, rerenderCallback);
//   } else {
//     nodeElement.addEventListener("click", (e) => {
//       editor?.destroy();

//       editor = new Editor({
//         element: editorElement,
//         extensions: [
//           AutoJoiner,
//           Collaboration.configure({ fragment: ydoc.getXmlFragment(nodeId) }),
//           GlobalDragHandle,
//           StarterKit.configure({
//             undoRedo: false,
//           }),
//         ],
//       });

//       console.log("note clicked", node.name);
//     });
//   }
//   // Create container for children
//   const childContainer = document.createElement("div");
//   container.appendChild(childContainer);

//   // Recursively render children
//   yTree.getNodeChildrenFromKey(nodeId).forEach((childId) => {
//     renderTreeStyled(
//       yTree,
//       childId,
//       childContainer,
//       indent + 1,
//       nodeId,
//       rerenderCallback
//     );
//   });

//   // Add final drop indicator for end of folder
//   if (node.type === "folder") {
//     const finalDropIndicator = createDropIndicator();
//     childContainer.appendChild(finalDropIndicator);
//     setupFinalDropIndicator(
//       finalDropIndicator,
//       yTree,
//       nodeId,
//       rerenderCallback
//     );
//   }
// }

// // Main render function that includes rerender callback
// export function renderDraggableTree(
//   yTree: Ytree,
//   rootNodeIds: string[],
//   container: HTMLElement
// ): void {
//   const rerenderCallback = () => {
//     container.innerHTML = "";
//     rootNodeIds.forEach((nodeId) => {
//       renderTreeStyled(yTree, nodeId, container, 0, "root", rerenderCallback);
//     });
//   };

//   // Initial render
//   rerenderCallback();
// }

// // CSS styles to be added to your page (add these to your stylesheet)
// export const dragDropStyles = `
//   .tree-node.dragging {
//     opacity: 0.5;
//   }

//   .tree-node.drop-target {
//     background-color: #1e40af !important;
//     transform: scale(1.02);
//   }

//   .tree-node.drop-target::before {
//     content: '';
//     position: absolute;
//     left: 0;
//     right: 0;
//     top: 0;
//     bottom: 0;
//     border: 2px dashed #60a5fa;
//     border-radius: 4px;
//     pointer-events: none;
//   }

//   .drop-indicator {
//     height: 2px;
//     background-color: #60a5fa;
//     border-radius: 1px;
//     transition: all 0.2s ease;
//     margin: 2px 0;
//   }

//   .drop-indicator.hidden {
//     opacity: 0;
//     height: 0;
//     margin: 0;
//   }
// `;
// import { IndexeddbPersistence } from "y-indexeddb";

// import { Editor, Extension } from "@tiptap/core";
// import { keymap } from "@tiptap/pm/keymap";
// import StarterKit from "@tiptap/starter-kit";
// import GlobalDragHandle from "tiptap-extension-global-drag-handle";
// import AutoJoiner from "tiptap-extension-auto-joiner";
// import CommentExtension from "@sereneinserenade/tiptap-comment-extension";
// import Collaboration from "@tiptap/extension-collaboration";
// import CollaborationCaret from "@tiptap/extension-collaboration-caret";

// const app = document.getElementById("file-system")!;
// const ydoc = new Y.Doc();
// const provider = new IndexeddbPersistence("room", ydoc);

// const editorElement = document.querySelector(".editor");
// if (!editorElement) {
//   throw new Error('Editor element with class "editor" not found');
// }
// let editor: Editor | undefined;

// provider.whenSynced.then((e) => {
//   const yMap = ydoc.getMap("ytree");

//   let yTree: Ytree = new YTree(yMap);
//   renderDraggableTree(yTree, yTree.getNodeChildrenFromKey("root"), app);
// });
