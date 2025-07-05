// import { Editor, Extension } from "@tiptap/core";
import { keymap } from "@tiptap/pm/keymap";

// Yjs imports (no WebsocketProvider since we're using custom WebSocket)
import Dexie, { type EntityTable } from "dexie";

import {
  LoroSyncPlugin,
  LoroUndoPlugin,
  redo,
  undo,
  CursorAwareness,
  LoroCursorPlugin,
} from "loro-prosemirror";

import {
  LoroDoc,
  LoroTree,
  LoroTreeNode,
  LoroMap,
  LoroText,
  ContainerID,
  TreeID,
} from "loro-crdt";

import * as sdk from "matrix-js-sdk";
const ROOT_DOC_KEY = "0@14167320934836008919";
let matrixClient: sdk.MatrixClient;

import { AutoDiscovery } from "matrix-js-sdk";
import {
  isLivekitFocusConfig,
  LivekitFocus,
} from "matrix-js-sdk/src/matrixrtc/LivekitFocus";
import {
  MatrixRTCSession,
  MatrixRTCSessionEvent,
} from "matrix-js-sdk/src/matrixrtc/MatrixRTCSession";

const FOCI_WK_KEY = "org.matrix.msc4143.rtc_foci";

import { MatrixClient, type IOpenIDToken } from "matrix-js-sdk/src/matrix";
import { logger } from "matrix-js-sdk/src/logger";

import { Room, RoomEvent } from "livekit-client";
import { sleep } from "matrix-js-sdk/src/utils";

export interface SFUConfig {
  url: string;
  jwt: string;
}
export type OpenIDClientParts = Pick<
  MatrixClient,
  "getOpenIdToken" | "getDeviceId"
>;

function getRandomAnimalName() {
  const animals = [
    "Lion",
    "Tiger",
    "Elephant",
    "Giraffe",
    "Zebra",
    "Monkey",
    "Panda",
    "Koala",
    "Kangaroo",
    "Dolphin",
    "Whale",
    "Shark",
    "Eagle",
    "Owl",
    "Parrot",
    "Penguin",
    "Flamingo",
    "Bear",
    "Wolf",
    "Fox",
    "Rabbit",
    "Deer",
    "Horse",
    "Cat",
    "Hamster",
    "Hedgehog",
    "Squirrel",
    "Raccoon",
    "Otter",
    "Seal",
    "Turtle",
    "Frog",
    "Butterfly",
    "Bee",
    "Ladybug",
    "Spider",
    "Octopus",
    "Jellyfish",
    "Starfish",
    "Crab",
    "Lobster",
    "Shrimp",
    "Salmon",
    "Tuna",
    "Goldfish",
    "Seahorse",
    "Crocodile",
    "Lizard",
    "Snake",
    "Chameleon",
  ];

  return animals[Math.floor(Math.random() * animals.length)];
}

// Function to get a random color in hex format
function getRandomColor() {
  const colors = [
    "#6DFF7E", // Green
    "#FF6D6D", // Red
    "#6D9EFF", // Blue
    "#FFD66D", // Yellow
    "#FF6DFF", // Magenta
    "#6DFFFF", // Cyan
    "#FF9D6D", // Orange
    "#A06DFF", // Purple
    "#FF6DA0", // Pink
    "#6DFFA0", // Mint
    "#FFA06D", // Peach
    "#A0FF6D", // Lime
    "#6DA0FF", // Sky Blue
    "#FF6DDE", // Hot Pink
    "#DFF6D6", // Light Green
    "#FFB3BA", // Light Pink
    "#BAFFC9", // Light Mint
    "#BAE1FF", // Light Blue
    "#FFFFBA", // Light Yellow
    "#FFDFBA", // Light Orange
  ];

  return colors[Math.floor(Math.random() * colors.length)];
}

export async function makePreferredLivekitFoci(
  rtcSession: MatrixRTCSession,
  livekitAlias: string,
  matrix_client: MatrixClient
): Promise<LivekitFocus[]> {
  console.log("Start building foci_preferred list: ", rtcSession.room.roomId);

  const preferredFoci: LivekitFocus[] = [];

  // Prioritize the .well-known/matrix/client, if available, over the configured SFU
  const domain = matrix_client.getDomain();
  if (domain) {
    // we use AutoDiscovery instead of relying on the MatrixClient having already
    // been fully configured and started
    const wellKnownFoci = (await AutoDiscovery.getRawClientConfig(domain))?.[
      FOCI_WK_KEY
    ];
    if (Array.isArray(wellKnownFoci)) {
      preferredFoci.push(
        ...wellKnownFoci
          .filter((f) => !!f)
          .filter(isLivekitFocusConfig)
          .map((wellKnownFocus) => {
            console.log(
              "Adding livekit focus from well known: ",
              wellKnownFocus
            );
            return { ...wellKnownFocus, livekit_alias: livekitAlias };
          })
      );
    }
  }
  return preferredFoci;
}
async function getLiveKitJWT(
  client: OpenIDClientParts,
  livekitServiceURL: string,
  roomName: string,
  openIDToken: IOpenIDToken
): Promise<SFUConfig> {
  try {
    const res = await fetch(livekitServiceURL + "/sfu/get", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        room: roomName,
        openid_token: openIDToken,
        device_id: client.getDeviceId(),
      }),
    });
    if (!res.ok) {
      throw new Error("SFU Config fetch failed with status code " + res.status);
    }
    const sfuConfig = await res.json();
    console.log(
      "MatrixRTCExample: get SFU config: \nurl:",
      sfuConfig.url,
      "\njwt",
      sfuConfig.jwt
    );
    return sfuConfig;
  } catch (e) {
    throw new Error("SFU Config fetch failed with exception " + e);
  }
}

export async function getSFUConfigWithOpenID(
  client: OpenIDClientParts,
  activeFocus: LivekitFocus
): Promise<SFUConfig | undefined> {
  const openIdToken = await client.getOpenIdToken();
  logger.debug("Got openID token", openIdToken);

  try {
    logger.info(
      `Trying to get JWT from call's active focus URL of ${activeFocus.livekit_service_url}...`
    );
    const sfuConfig = await getLiveKitJWT(
      client,
      activeFocus.livekit_service_url,
      activeFocus.livekit_alias,
      openIdToken
    );
    logger.info(`Got JWT from call's active focus URL.`);

    return sfuConfig;
  } catch (e) {
    logger.warn(
      `Failed to get JWT from RTC session's active focus URL of ${activeFocus.livekit_service_url}.`,
      e
    );
    return undefined;
  }
}
//@ts-ignore
import { Ok, Error } from "../gleam.mjs";

export async function login_matrix(
  access_token: string,
  user_id: string,
  device_id: string
) {
  matrixClient = sdk.createClient({
    baseUrl: "https://matrix.org",
    accessToken: access_token,
    deviceId: device_id,
    userId: user_id,
  });

  // console.log("access_token found : " + access_token);
  try {
    await matrixClient.initRustCrypto();
    await matrixClient.startClient();

    // Validate the token by making an authenticated request
    const whoami = await matrixClient.whoami();
    // console.log("Token validated for user:", whoami.user_id);

    return new Ok(matrixClient);
  } catch {
    matrixClient.stopClient();
    indexedDB.deleteDatabase("matrix-js-sdk::matrix-sdk-crypto");
    console.log("Token Is invalid.");
    return new Error(
      "Token Is invalid. You have been logged out. Refresh the page"
    );
  }
}
export async function login_sso() {
  matrixClient = sdk.createClient({ baseUrl: "https://matrix.org" });

  const redirectUri = window.location.origin + "/login/";

  const ssoUrl = matrixClient.getSsoLoginUrl(
    redirectUri,
    undefined,
    "m.login.sso"
  );

  window.location.href = ssoUrl;
}

export async function get_login_sso() {
  if (window.location.pathname === "/login/") {
    const params = new URLSearchParams(window.location.search);
    const access_token = params.get("loginToken");

    if (!access_token) {
      console.error("Missing SSO credentials in URL fragment");
      return new Error("Missing SSO credentials in URL fragment");
    } else {
      const url = new URL(window.location.origin + "/");
      url.searchParams.delete("loginToken");
      window.history.replaceState(
        {},
        document.title,
        url.pathname + url.search
      );

      matrixClient = sdk.createClient({
        baseUrl: "https://matrix.org",
        accessToken: access_token,
      });

      try {
        const loginData = {
          type: "m.login.token",
          token: access_token,
        };
        const response = await matrixClient.loginRequest(loginData);
        // Set the access token and userId manually, since loginRequest doesn't do this automatically
        matrixClient.http.opts.accessToken = response.access_token;
        matrixClient.credentials = {
          userId: response.user_id,
        };
        matrixClient.deviceId = response.device_id;

        console.log("Matrix client connected");
        localStorage.setItem("access_token", matrixClient.getAccessToken()!);
        localStorage.setItem("device_id", matrixClient.getDeviceId()!);
        localStorage.setItem("user_id", matrixClient.getUserId()!);

        await matrixClient.initRustCrypto(); // Must be called after setting credentials
        await matrixClient.startClient();

        return new Ok(matrixClient);
      } catch (error) {
        indexedDB.deleteDatabase("matrix-js-sdk::matrix-sdk-crypto");
        console.error("Matrix login failed:", error);
        let message = "Matrix login failed: \n" + error;
        return new Error(message);
      }
    }
  } else {
    return new Error("");
  }
}

export function get_rooms(matrixClient: sdk.MatrixClient) {
  matrixClient.removeAllListeners(sdk.ClientEvent.Sync);

  matrixClient.on(sdk.ClientEvent.Sync, () => {
    const currentRooms = matrixClient.getRooms();

    const mainApp = document.querySelector("#main-app");
    if (mainApp) {
      const messageEvent = new CustomEvent("rooms_updated", {
        detail: currentRooms,
      });
      mainApp.dispatchEvent(messageEvent);
    }
  });
}
export function save_document() {
  const mainApp = document.querySelector("#main-app");
  if (mainApp) {
    const messageEvent = new CustomEvent("save_doc");
    mainApp.dispatchEvent(messageEvent);
  }
}

export async function save_function(room_id: string, doc: LoroDoc) {
  const stateEvents = await matrixClient.roomState(room_id);

  const loroEvents = stateEvents.filter((event) =>
    event.type.startsWith("loro.doc")
  );
  const importPromises = loroEvents.map(async (event) => {
    try {
      const mxcUrl = event.content.url;
      const url = matrixClient.mxcUrlToHttp(
        mxcUrl,
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        true // useAuthentication
      )!;

      const response = await fetch(url, {
        headers: {
          Authorization: `Bearer ${matrixClient.getAccessToken()}`,
        },
      });

      if (!response.ok) {
        console.warn(`Failed to fetch Loro document from ${url}`);
        return null;
      }

      const body = await response.arrayBuffer();
      return new Uint8Array(body);
    } catch (error) {
      console.error("Error importing Loro document:", error);
      return null;
    }
  });

  const uint8Arrays = (await Promise.all(importPromises)).filter(
    Boolean
  ) as Uint8Array[];

  doc.importBatch(uint8Arrays);

  const snapshot = doc.export({
    mode: "snapshot",
  });
  await save_loro_doc(room_id, doc);

  const mxcUrl = await matrixClient.http.uploadContent(snapshot, {
    type: "application/octet-stream",
    name: "loro-doc.bin",
  });

  let url = mxcUrl.content_uri;

  await matrixClient.sendStateEvent(
    room_id, //@ts-ignore
    "loro.doc." + matrixClient.getDeviceId()!,
    {
      type: "update",
      url: url,
    },
    matrixClient.getUserId()!
  );

  const mainApp = document.querySelector("#main-app");
  if (mainApp) {
    const messageEvent = new CustomEvent("state_saved");
    mainApp.dispatchEvent(messageEvent);
  }
}

export function user_selected_note(note_id: String) {
  const mainApp = document.querySelector("#main-app");

  if (mainApp) {
    const messageEvent = new CustomEvent("user-selected-note", {
      detail: note_id,
    });

    mainApp.dispatchEvent(messageEvent);
  }
}

export function download_notebook(doc: LoroDoc) {
  let snapshot = doc.export({ mode: "snapshot" });
  // Convert Uint8Array to Blob
  const blob = new Blob([snapshot], { type: "application/octet-stream" });

  // Create download link
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "MyNoteBook.bin"; // or whatever filename you want
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
//@ts-ignore
import { render_editor, create_root } from "./main.jsx";

export async function init_tiptap(
  doc: LoroDoc,
  matrixClient: MatrixClient,
  room_id: string
) {
  const awareness = new CursorAwareness(doc.peerIdStr);

  const mainApp = document.querySelector("#main-app");

  let selected_document;

  // // let awareness;
  // let tiptapEditor: Editor | undefined;
  let livekitRoom: Room;
  let tiptapEditor;
  let blocknoteEditor: BlockNoteEditor | undefined;
  if (mainApp) {
    mainApp.addEventListener("user-selected-note", (e) => {
      if (tiptapEditor) {
        tiptapEditor.destroy();

        //@ts-ignore
        selected_document = e.detail;
        let container = doc.getMap(selected_document);
        const LoroPlugins = Extension.create({
          name: "loro-plugins",
          addProseMirrorPlugins() {
            return [
              LoroSyncPlugin({
                //@ts-ignore
                doc,
                containerId: container.id,
              }),
              LoroUndoPlugin({ doc }),
              LoroCursorPlugin(awareness, {
                user: {
                  name: matrixClient!.getUser(matrixClient.getUserId()!)!
                    .rawDisplayName!,
                  color: getRandomColor(),
                },
              }),
              keymap({ "Mod-z": undo, "Mod-y": redo, "Mod-Shift-z": redo }),
            ];
          },
        });

        render_editor(LoroPlugins, (tiptapEditor, blocknoteEditor) => {
          tiptapEditor = tiptapEditor;
          blocknoteEditor = blocknoteEditor;
        });
      } else {
        //@ts-ignore
        selected_document = e.detail;
        let container = doc.getMap(selected_document);
        const LoroPlugins = Extension.create({
          name: "loro-plugins",
          addProseMirrorPlugins() {
            return [
              LoroSyncPlugin({
                //@ts-ignore
                doc,
                containerId: container.id,
              }),
              LoroUndoPlugin({ doc }),
              LoroCursorPlugin(awareness, {
                user: {
                  name: matrixClient!.getUser(matrixClient.getUserId()!)!
                    .rawDisplayName!,
                  color: getRandomColor(),
                },
              }),
              keymap({ "Mod-z": undo, "Mod-y": redo, "Mod-Shift-z": redo }),
            ];
          },
        });

        render_editor(LoroPlugins, (tiptapEditor, blocknoteEditor) => {
          tiptapEditor = tiptapEditor;
          blocknoteEditor = blocknoteEditor;
        });
      }
    });
  }
  matrixClient.once(sdk.ClientEvent.Sync, async (state, prev_state, res) => {
    const matrix_room = matrixClient.getRoom(room_id);
    if (!matrix_room) {
      // Create and dispatch custom event

      // throw new Error("Room not found after sync");
      if (mainApp) {
        let message =
          "I couldn't join the rrom you provided please check that this room ID is correct then refresh the page \n the room ID you inserted: \n\n" +
          room_id;
        const messageEvent = new CustomEvent("error_sent", {
          detail: message,
        });
        mainApp.dispatchEvent(messageEvent);
      }
    } else {
      const session = matrixClient.matrixRTC.getRoomSession(matrix_room);

      const focus = (
        await makePreferredLivekitFoci(
          session,
          matrix_room.roomId,
          matrixClient
        )
      )[0];

      const sfuConfig = await getSFUConfigWithOpenID(matrixClient, focus);
      if (!sfuConfig) throw "Could not get SFU config from the jwt service";

      livekitRoom = new Room({});

      livekitRoom.connect(sfuConfig.url, sfuConfig.jwt);

      save_function(room_id, doc);

      const mainApp = document.querySelector("#main-app");
      if (mainApp) {
        mainApp.addEventListener("save_doc", () => {
          save_function(room_id, doc);
        });
      }

      let seconds = 300;

      setInterval(async () => save_function(room_id, doc), seconds * 1000);

      livekitRoom.on("participantConnected", async (participant) => {
        let update = doc.export({ mode: "update" });

        const writer = await livekitRoom.localParticipant.streamBytes({
          // All byte streams must have a name, which is like a filename
          name: "loro-update",
          // Fixed typo: "updare" -> "update"
          topic: "loro-update",
        });

        const chunkSize = 15000; // 15KB, a recommended max chunk size

        // Stream the Uint8Array update data in chunks
        for (let i = 0; i < update.length; i += chunkSize) {
          const chunk = update.slice(i, i + chunkSize);
          await writer.write(chunk);
        }

        await writer.close();
      });
      livekitRoom.on("connected", async () => {
        let update = doc.export({ mode: "update" });

        const writer = await livekitRoom.localParticipant.streamBytes({
          // All byte streams must have a name, which is like a filename
          name: "loro-update",
          // Fixed typo: "updare" -> "update"
          topic: "loro-update",
        });

        const chunkSize = 15000; // 15KB, a recommended max chunk size

        // Stream the Uint8Array update data in chunks
        for (let i = 0; i < update.length; i += chunkSize) {
          const chunk = update.slice(i, i + chunkSize);
          await writer.write(chunk);
        }

        await writer.close();

        doc.subscribe(async (e) => {
          let update = doc.export({ mode: "update" });

          const writer = await livekitRoom.localParticipant.streamBytes({
            // All byte streams must have a name, which is like a filename
            name: "loro-update",
            // Fixed typo: "updare" -> "update"
            topic: "loro-update",
          });

          const chunkSize = 15000; // 15KB, a recommended max chunk size

          // Stream the Uint8Array update data in chunks
          for (let i = 0; i < update.length; i += chunkSize) {
            const chunk = update.slice(i, i + chunkSize);
            await writer.write(chunk);
          }

          await writer.close();

          // // The stream must be explicitly closed when done
          // try await writer.close()

          // livekitRoom.localParticipant.publishData(data, {
          //   reliable: false,
          // });
          await save_loro_doc(room_id, doc);
        });

        let debounceTimer;

        awareness.addListener(async (update, origin) => {
          // Clear existing timer
          if (debounceTimer) {
            clearTimeout(debounceTimer);
          }

          // Set new timer with 100ms delay
          debounceTimer = setTimeout(async () => {
            if (origin === "local") {
              if (selected_document) {
                const update = awareness.encode([doc.peerIdStr]);

                const writer = await livekitRoom.localParticipant.streamBytes({
                  // All byte streams must have a name, which is like a filename
                  name: selected_document,
                  // Fixed typo: "updare" -> "update"
                  topic: "loro-awareness",
                });

                const chunkSize = 15000; // 15KB, a recommended max chunk size

                // Stream the Uint8Array update data in chunks
                for (let i = 0; i < update.length; i += chunkSize) {
                  const chunk = update.slice(i, i + chunkSize);
                  await writer.write(chunk);
                }

                await writer.close();
              }
            }
          }, 100);
        });
      });

      livekitRoom.registerByteStreamHandler(
        "loro-update",
        async (reader, participantInfo) => {
          const info = reader.info;

          // Option 2: Get the entire file after the stream completes.
          const result = new Blob(await reader.readAll(), {
            type: info.mimeType,
          });

          const update = new Uint8Array(await result.arrayBuffer());
          doc.import(update);
        }
      );
      livekitRoom.registerByteStreamHandler(
        "loro-awareness",
        async (reader, participantInfo) => {
          const info = reader.info;

          // Option 2: Get the entire file after the stream completes.
          const result = new Blob(await reader.readAll(), {
            type: info.mimeType,
          });

          const update = new Uint8Array(await result.arrayBuffer());
          awareness.apply(update);
        }
      );
    }
  });
}
export function delete_db() {
  indexedDB.deleteDatabase("matrix-js-sdk::matrix-sdk-crypto");
}

import {
  draggable,
  dropTargetForElements,
} from "@atlaskit/pragmatic-drag-and-drop/element/adapter";
import { Extension } from "@tiptap/core";
import { BlockNoteEditor } from "@blocknote/core";

export function make_draggable(folders_and_items: [HTMLElement]) {
  folders_and_items.forEach((element) => {
    draggable({
      element: element,
    });
  });
}

export function make_drop_target(
  folders: [HTMLElement],
  handleDragEnter,
  handleDragLeave,
  handleDrop
) {
  folders.forEach((folder_element) => {
    dropTargetForElements({
      element: folder_element,
      canDrop(e) {
        let item = e.source.element.dataset.drag_id;
        let drop_target = folder_element.dataset.drag_id;
        if (item === drop_target) {
          return false;
        }
        if (
          folder_element.dataset.drag_id === e.source.element.dataset.parent_id
        ) {
          return false;
        }
        if (
          folder_element.dataset.drag_id === folder_element.dataset.parent_id
        ) {
          return false;
        } else {
          return true;
        }
      },
      onDragEnter: () => {
        handleDragEnter(folder_element.dataset.drag_id);
      },
      onDragLeave: () => {
        handleDragLeave(folder_element.dataset.drag_id);
      },

      onDrop: (e) => {
        let item = e.source.element.dataset.drag_id;

        let drop_target = folder_element.dataset.drag_id;
        let drop_target_type = folder_element.dataset.item_type;
        let drop_target_parent_id = folder_element.dataset.parent_id;

        if (drop_target_type === "folder") {
          handleDrop(item, drop_target);
        } else {
          handleDrop(item, drop_target_parent_id);
        }
      },
    });
  });
}

export function get_tree(doc: LoroDoc, room_id: string, on_tree) {
  let tree: LoroTree = doc.getTree("tree");
  // tree.enableFractionalIndex(0);
  let root = tree.createNode();
  root.data.set("name", "root");
  root.data.set("item_type", "folder");

  // let folder1 = root.createNode();
  // folder1.data.set("name", "folder1");
  // folder1.data.set("item_type", "folder");

  // let folder2 = root.createNode();
  // folder2.data.set("name", "folder2");
  // folder2.data.set("item_type", "folder");

  // let file_1 = folder1.createNode();

  // file_1.data.set("name", "README.md");
  // file_1.data.set("item_type", "file");

  // let file_2 = folder2.createNode();

  // file_2.data.set("name", "gleam.toml");
  // file_2.data.set("item_type", "file");

  doc.subscribe(() => {
    let json = JSON.stringify(tree.toArray()[0]);
    on_tree(json);
    save_loro_doc(room_id, doc);
  });
  doc.commit();

  let json = JSON.stringify(tree.toArray()[0]);
  return json;
}

interface File {
  id: string; // room_id will be used as the primary key
  content: Uint8Array;
}

export async function create_loro_doc(room_id: string) {
  const db = new Dexie(room_id) as Dexie & {
    files: EntityTable<File, "id">;
  };

  // Schema declaration:
  db.version(1).stores({
    files: "id, content", // id is the primary key (room_id)
  });

  try {
    // Try to get existing document from Dexie using room_id
    const existingFile = await db.files.get(room_id);

    let doc: LoroDoc;
    if (existingFile && existingFile.content) {
      // const binaryString = atob(existingFile.content);
      // const snapshot = new Uint8Array(binaryString.length);
      // for (let i = 0; i < binaryString.length; i++) {
      //   snapshot[i] = binaryString.charCodeAt(i);
      // }

      doc = LoroDoc.fromSnapshot(existingFile.content);
      doc.setRecordTimestamp(true);
      return doc;
    } else {
      // Create new document with default content (a tree with a root document that dosen't have any children)
      let updateString =
        "bG9ybwAAAAAAAAAAAAAAALMgzjMAA9AAAABMT1JPAAHX7+veweqbzsQBBAACAHZ2Adfv697B6pvOxAEGAAwAxJxvVBva99cAAAAAAAMAAwEQAdf32htUb5zEAQEAAAAAAAUBAAABAAsCBAEDAAQEAAAAABQEbmFtZQlpdGVtX3R5cGUEdHJlZQkBAgIBAAMBAYAUAQQEBQACAAQEAAECBAEQBAsCBgEAEgAAAAEFBHJvb3QFBmZvbGRlcgAADAAdAAMAsImQGgEAAAAFAAAAAgBmcgAMAMScb1Qb2vfXAAAAADIPFQStAAAAogAAAExPUk8ABCJNGGBAgmIAAADxKwACAQAEdHJlZQQCCWl0ZW1fdHlwZQQGZm9sZGVyBG5hbWUEBHJvb3QAAdf32htUb5zEAAIAAQAGAIM2ACYDARkAQAQCAgFPABIFBwAFBgAgCQEZALADAQGAAAAANgACAAAAAACmP6p3AQAAAAUAAAANAADX99obVG+cxAAAAAABBgCDBHRyZWWhk7SsegAAAAAAAAA=";

      const binaryString = atob(updateString);
      const snapshot = new Uint8Array(binaryString.length);
      for (let i = 0; i < binaryString.length; i++) {
        snapshot[i] = binaryString.charCodeAt(i);
      }

      doc = LoroDoc.fromSnapshot(snapshot);
      doc.setRecordTimestamp(true);
      // Save the initial document to Dexie with room_id as the key
      await db.files.put({
        id: room_id,
        content: snapshot,
      });

      return doc;
    }
  } catch (error) {
    console.error("Error accessing Dexie database:", error);
    throw error;
  }
}

// Helper function to save document updates to Dexie
export async function save_loro_doc(room_id: string, doc: LoroDoc) {
  const db = new Dexie(room_id) as Dexie & {
    files: EntityTable<File, "id">;
  };

  db.version(1).stores({
    files: "id, content", // id is the primary key (room_id)
  });

  try {
    const snapshot = doc.export({ mode: "snapshot" });
    // const base64String = btoa(String.fromCharCode(...snapshot));

    // Update or create the file with room_id as the key
    await db.files.put({
      id: room_id,
      content: snapshot,
    });
  } catch (error) {
    console.error("Error saving to Dexie database:", error);
    throw error;
  }
}

export function create_new_note(doc: LoroDoc, item_id) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    let note = tree.createNode(item_id);
    note.data.set("item_type", "file");
    // note.data.set("name", "Untitled");

    doc.commit();
  } catch (error) {
    console.log("Delete failed", error);
  }
}

export function create_new_folder(doc: LoroDoc, item_id) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    let folder = tree.createNode(item_id);
    folder.data.set("item_type", "folder");
    doc.commit();
  } catch (error) {
    console.log("Delete failed", error);
  }
}

export function move_item(
  doc: LoroDoc,
  item_id: TreeID,
  drop_target_id: TreeID
) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    tree.move(item_id, drop_target_id);

    doc.commit();
  } catch (error) {
    console.log("Move failed", error);
  }
}

export function delete_item(doc: LoroDoc, item_id: TreeID) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    tree.delete(item_id);

    doc.commit();
  } catch (error) {
    console.log("Delete failed", error);
  }
}

export function change_item_name(
  doc: LoroDoc,
  item_id: TreeID,
  item_name: String,
  item_name_changed
) {
  let tree: LoroTree = doc.getTree("tree");

  try {
    let item_node = tree.getNodeByID(item_id);

    if (item_node) {
      item_node.data.set("name", item_name);

      doc.commit();

      item_name_changed();
    } else {
      throw console.error();
    }
  } catch (error) {
    item_name_changed();
    console.log("Delete failed", error);
  }
}
