import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import grille_pain
import grille_pain/lustre/toast
import grille_pain/toast/level
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element as lustre_element
import lustre/element/svg
import lustre/event
import plinth/javascript/storage.{get_item, local, remove_item}
import sketch
import sketch/css.{class}
import sketch/css/length
import sketch/css/transform
import sketch/lustre as sketch_lustre
import sketch/lustre/element.{type Element}
import sketch/lustre/element/html

import plinth/browser/document
import plinth/browser/element as browser_element

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let assert Ok(_) = grille_pain.simple()
  let assert Ok(stylesheet) = sketch_lustre.setup()

  // Because stylesheets are persistents with sketch_lustre, you can inject
  // classes, keyframes or @rules directly in it.
  sketch.global(stylesheet, css.global("body", []))

  let app = lustre.application(init, update, view(_, stylesheet))

  let assert Ok(_) =
    lustre.start(
      app,
      "#app",
      Model(
        matrix_client: None,
        room: None,
        rooms: [],
        selected_rooms: [],
        selected_document: None,
        modal: False,
        filesystem_menu: None,
        loro_doc: None,
        tree: None,
        dragged_over_tree_item: None,
        edited_tree_item: None,
        selected_item_name: None,
        expanded_folders: [],
      ),
    )

  Nil
}

type LoroDoc

fn init_dnd() {
  use dispatch, _ <- effect.after_paint

  let tree_items: array.Array(browser_element.Element) =
    document.query_selector_all(".tree-item")

  let tree_item_list = tree_items |> array.to_list

  let filtered_drop_items =
    tree_item_list
    |> list.filter(fn(drop_item_element) {
      case
        drop_item_element
        |> browser_element.get_attribute("data-drop-target-for-element")
      {
        Ok(_) -> {
          False
          // case value {
          //   "true" ->

          //   _ -> {
          //     True
          //   }
        }
        Error(_) -> True
      }
    })
    |> array.from_list

  do_make_drop_target(
    folders: filtered_drop_items,
    on_drag_enter: fn(item_id) { dispatch(UserDraggedItemOver(item_id)) },
    on_drag_leave: fn(item_id) { dispatch(UserDraggedItemOff(item_id)) },
    on_drop: fn(item, folder) { dispatch(UserDroppedItem(item, folder)) },
  )

  let tree_item_list = tree_items |> array.to_list

  let filtered_tree_items =
    tree_item_list
    |> list.filter(fn(tree_item_element) {
      case tree_item_element |> browser_element.get_attribute("draggable") {
        Ok(_) -> False
        Error(_) -> True
      }
    })
    |> array.from_list

  do_make_draggable(filtered_tree_items)
}

@external(javascript, "./js/editor.ts", "make_drop_target")
fn do_make_drop_target(
  folders folders: array.Array(a),
  on_drag_enter on_drag_enter: fn(String) -> Nil,
  on_drag_leave on_drag_leave: fn(String) -> Nil,
  on_drop on_drop: fn(String, String) -> Nil,
) -> Nil

@external(javascript, "./js/editor.ts", "get_tree")
fn get_tree(loro_doc: LoroDoc, on_tree: fn(String) -> Nil) -> String

@external(javascript, "./js/editor.ts", "create_loro_doc")
fn create_loro_doc(room_id: String) -> LoroDoc

@external(javascript, "./js/editor.ts", "move_item")
fn do_move_item(loro_doc: LoroDoc, item: String, folder: String) -> Nil

@external(javascript, "./js/editor.ts", "delete_item")
fn do_delete_item(loro_doc: LoroDoc, item: String) -> Nil

@external(javascript, "./js/editor.ts", "change_item_name")
fn do_change_item_name(
  loro_doc: LoroDoc,
  item: String,
  item_name: String,
  on_change_name: fn() -> Nil,
) -> Nil

@external(javascript, "./js/editor.ts", "make_draggable")
fn do_make_draggable(elements: array.Array(a)) -> Nil

pub type Node {
  Node(
    id: String,
    parent: Option(String),
    index: Int,
    meta: Dict(String, decode.Dynamic),
    children: List(Node),
  )
}

pub fn node_decoder() {
  use id <- decode.field("id", decode.string)
  use parent <- decode.optional_field(
    "parent",
    None,
    decode.optional(decode.string),
  )
  use index <- decode.field("index", decode.int)
  use meta <- decode.field("meta", decode.dict(decode.string, decode.dynamic))
  use children <- decode.optional_field(
    "children",
    [],
    decode.list(node_decoder()),
  )

  decode.success(Node(
    id: id,
    parent: parent,
    index: index,
    meta: meta,
    children: children,
  ))
}

// MODEL -----------------------------------------------------------------------
type Model {
  Model(
    selected_document: Option(String),
    matrix_client: Option(MatrixClient),
    room: Option(String),
    rooms: List(Room),
    selected_rooms: List(String),
    modal: Bool,
    filesystem_menu: Option(List(String)),
    loro_doc: Option(LoroDoc),
    tree: Option(Node),
    dragged_over_tree_item: Option(String),
    edited_tree_item: Option(String),
    selected_item_name: Option(String),
    expanded_folders: List(String),
  )
}

fn init(model: Model) -> #(Model, Effect(Msg)) {
  #(model, login())
}

pub opaque type Msg {
  SaveDocument
  ToggleModal
  UserHasLoggedIn(MatrixClient)
  DisplayRooms(List(Room))
  StartSSOLogin
  EnterRoom(String, MatrixClient)
  DisplayBasicToast(String)
  DisplayErrorToast(String)
  AddRoom(String)
  RemoveRoom(String)
  DisplaySelectedRooms(List(String))

  LoroDocCreated(LoroDoc)
  UserDraggedItemOver(String)
  UserDraggedItemOff(String)
  RenderTree(Node)
  UserDroppedItem(String, String)
  DeleteItem(String)
  UserEditingItem(String)
  UserFinishedEditingItem(String)
  UserCanceledEditingItem
  ItemNameHasChanged(String)
  ToggleFolderExpanded(String)
  DoNothing
  DisplayFileSystemMenu(String, String)
  CreateNewNote(String)
  CreateNewFolder(String)
  HideFileSystemMenu
  UserSelectedNote(String)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    DoNothing -> #(model, effect.none())
    UserSelectedNote(note_id) -> {
      #(
        Model(..model, filesystem_menu: None, selected_document: Some(note_id)),
        user_selected_note(note_id),
      )
    }
    HideFileSystemMenu -> {
      #(Model(..model, filesystem_menu: None), effect.none())
    }
    DisplayFileSystemMenu(item_id, y) -> {
      #(Model(..model, filesystem_menu: Some([item_id, y])), effect.none())
    }
    CreateNewNote(item_id) -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          #(
            Model(..model, filesystem_menu: None),
            create_new_note(loro_doc, item_id),
          )
        }
        None -> {
          #(model, effect.none())
        }
      }
    }
    CreateNewFolder(item_id) -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          #(
            Model(..model, filesystem_menu: None),
            create_new_folder(loro_doc, item_id),
          )
        }
        None -> {
          #(model, effect.none())
        }
      }
    }
    DeleteItem(item_id) ->
      case model.loro_doc {
        Some(loro_doc) -> #(model, delete_item(loro_doc, item_id))
        None -> #(model, effect.none())
      }
    UserCanceledEditingItem -> #(
      Model(..model, selected_item_name: None, edited_tree_item: None),
      effect.none(),
    )

    ToggleFolderExpanded(folder_id) -> {
      let folder_id_list = model.expanded_folders

      case folder_id_list |> list.contains(folder_id) {
        True -> {
          let expanded_folders =
            folder_id_list |> list.filter(fn(id) { id != folder_id })
          #(
            Model(..model, filesystem_menu: None, expanded_folders:),
            init_dnd(),
          )
        }
        False -> {
          let expanded_folders = folder_id_list |> list.append([folder_id])
          #(
            Model(..model, filesystem_menu: None, expanded_folders:),
            init_dnd(),
          )
        }
      }
    }

    ItemNameHasChanged(name) -> {
      #(Model(..model, selected_item_name: Some(name)), effect.none())
    }

    UserEditingItem(item_id) -> #(
      Model(..model, edited_tree_item: Some(item_id)),
      effect.none(),
    )

    UserFinishedEditingItem(item_id) -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          case model.selected_item_name {
            Some(selected_item_name) -> {
              let trimmed_name = selected_item_name |> string.trim()
              #(
                Model(..model, selected_item_name: None),
                change_item_name(loro_doc, item_id, trimmed_name),
              )
            }
            None -> #(
              Model(..model, selected_item_name: None, edited_tree_item: None),
              effect.none(),
            )
          }
        }
        None -> #(model, effect.none())
      }
    }

    LoroDocCreated(loro_doc) -> #(
      Model(..model, loro_doc: Some(loro_doc)),
      effect.none(),
    )
    UserDraggedItemOver(id) -> #(
      Model(..model, dragged_over_tree_item: Some(id)),
      effect.none(),
    )
    UserDroppedItem(item, folder) -> {
      #(Model(..model, dragged_over_tree_item: None), case model.loro_doc {
        Some(loro_doc) -> {
          move_item(loro_doc, item, folder)
        }

        None -> {
          effect.none()
        }
      })
    }
    UserDraggedItemOff(id) -> {
      #(
        case model.dragged_over_tree_item {
          Some(dragged_item) -> {
            case dragged_item == id {
              True -> Model(..model, dragged_over_tree_item: None)
              False -> model
            }
          }
          None -> model
        },
        effect.none(),
      )
    }
    RenderTree(root) -> {
      case model.tree {
        Some(_old_tree) -> {
          #(Model(..model, tree: Some(root)), init_dnd())
        }
        None -> {
          #(Model(..model, tree: Some(root)), init_dnd())
        }
      }
    }

    SaveDocument -> #(model, save_document())
    ToggleModal -> #(Model(..model, modal: !model.modal), effect.none())
    StartSSOLogin -> #(model, login_sso())
    UserHasLoggedIn(matrix_client) -> #(
      Model(..model, matrix_client: Some(matrix_client)),
      effect.batch([
        success_toast("Connected to Matrix Correctly"),
        get_rooms(matrix_client),
      ]),
    )

    EnterRoom(room_id, matrix_client) -> {
      #(
        Model(..model, room: Some(room_id)),
        init_tiptap(matrix_client, room_id),
      )
    }
    AddRoom(room_id) -> {
      #(model, add_room(room_id))
    }
    RemoveRoom(room_id) -> {
      #(model, remove_room(room_id))
    }
    DisplayRooms(rooms) -> #(Model(..model, rooms:), effect.none())
    DisplaySelectedRooms(selected_rooms) -> #(
      Model(..model, selected_rooms:),
      effect.none(),
    )
    DisplayBasicToast(content) -> #(model, success_toast(content))
    DisplayErrorToast(content) -> #(model, error_toast(content))
  }
}

fn view(model: Model, stylesheet) -> Element(Msg) {
  use <- sketch_lustre.render(stylesheet:, in: [sketch_lustre.node()])

  let on_recive_error =
    event.on("error_sent", {
      use error_message <- decode.field("detail", decode.string)
      decode.success(DisplayErrorToast(error_message))
    })
  let on_recive_error_abort =
    event.on("error_abort", {
      use error_message <- decode.field("detail", decode.string)
      decode.success(DisplayErrorToast(error_message))
    })
  let on_state_saved =
    event.on("state_saved", {
      decode.success(DisplayBasicToast(
        "State Has Been Saved Correctly (this will run every 5 minutes)",
      ))
    })
  let on_rooms_updated =
    event.on("rooms_updated", {
      use rooms <- decode.field("detail", decode.list(decode.dynamic))

      let decode_room = {
        use name <- decode.field("name", decode.string)
        use room_id <- decode.field("roomId", decode.string)
        decode.success(Room(name:, room_id:))
      }

      let list =
        rooms
        |> list.map(fn(room) { decode.run(room, decode_room) })
        |> result.values

      decode.success(DisplayRooms(list))
    })
  let button =
    class([
      css.background("rgba(220, 38, 127, 0.8)"),
      css.color("#ffffff"),
      css.border("none"),
      css.border_radius(length.px(8)),
      css.padding_("12px 20px"),
      // css.margin_bottom(length.px(20)),
      css.cursor("pointer"),
      css.font_weight("500"),
      css.transition("all 0.2s ease"),
      css.hover([
        css.background("rgba(220, 38, 127, 1)"),
        css.transform([transform.translate_y(length.px(-1))]),
      ]),
    ])
  let page =
    class([
      css.display("flex"),
      css.flex_direction("column"),
      css.align_items("center"),
      css.justify_content("center"),
      css.font_family("Segoe UI, sans-serif"),
      css.color("white"),
      css.padding(length.px(32)),
      css.text_align("center"),
      css.gap(length.px(24)),
    ])

  html.div(
    class([]),
    [
      on_recive_error_abort,
      on_rooms_updated,
      on_recive_error,
      on_state_saved,
      attribute.id("main-app"),
    ],
    case model.matrix_client {
      None -> {
        [
          html.div(page, [], [
            html.h1(
              class([
                css.font_size(length.px(28)),
                css.margin_bottom(length.px(16)),
              ]),
              [],
              [html.text("Matrix SSO Login")],
            ),
            html.button(button, [event.on_click(StartSSOLogin)], [
              html.text("Login Using Matrix"),
            ]),
          ]),
        ]
      }
      Some(matrix_client) -> {
        case model.room {
          Some(_) -> {
            [
              case model.modal {
                True -> {
                  html.div(
                    class([
                      css.position("fixed"),
                      css.top(length.rem(0.8)),
                      css.right(length.rem(0.8)),
                      css.padding(length.rem(1.0)),
                      css.background(
                        "linear-gradient(135deg, rgba(26, 26, 46, 0.95) 0%, rgba(22, 33, 62, 0.95) 100%)",
                      ),
                      css.border_radius(length.px(16)),
                      css.box_shadow(
                        "0 12px 40px rgba(0, 0, 0, 0.25), 0 4px 12px rgba(220, 38, 127, 0.15), inset 0 1px 0 rgba(255, 255, 255, 0.1)",
                      ),
                      css.backdrop_filter("blur(16px)"),
                      css.border("1px solid rgba(255, 255, 255, 0.08)"),
                      css.z_index(100),
                    ]),
                    [],
                    [
                      html.div(
                        class([
                          css.display("flex"),
                          css.direction("rtl"),
                          css.flex_direction("row"),
                          css.gap(length.rem(0.75)),
                        ]),
                        [],
                        [
                          html.button(
                            class([
                              css.z_index(200),
                              css.display("flex"),
                              css.align_items("center"),
                              css.justify_content("center"),
                              css.width(length.rem(3.0)),
                              css.height(length.rem(3.0)),
                              css.background(
                                "linear-gradient(135deg, rgba(220, 38, 127, 0.9), rgba(180, 28, 100, 0.9))",
                              ),
                              css.border("1px solid rgba(255, 255, 255, 0.12)"),
                              css.color("#ffffff"),
                              css.border_radius(length.px(12)),
                              css.cursor("pointer"),
                              css.font_size(length.rem(1.3)),
                              css.font_weight("600"),
                              css.letter_spacing("0.5px"),
                              css.transition(
                                "all 0.3s cubic-bezier(0.4, 0, 0.2, 1)",
                              ),
                              css.box_shadow(
                                "0 6px 20px rgba(220, 38, 127, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.25)",
                              ),
                              css.hover([
                                css.background(
                                  "linear-gradient(135deg, rgba(220, 38, 127, 1), rgba(240, 48, 140, 1))",
                                ),
                                css.transform([
                                  transform.translate_y(length.px(-3)),
                                  transform.scale(1.02, 1.08),
                                ]),
                                css.box_shadow(
                                  "0 10px 30px rgba(220, 38, 127, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.35)",
                                ),
                                css.border(
                                  "1px solid rgba(255, 255, 255, 0.25)",
                                ),
                              ]),
                              css.active([
                                css.transform([
                                  transform.translate_y(length.px(-1)),
                                ]),
                              ]),
                            ]),
                            [event.on_click(ToggleModal)],
                            [menu_svg(" #FFFFFF ")],
                          ),
                          html.button(
                            class([
                              css.z_index(200),
                              css.display("flex"),
                              css.align_items("center"),
                              css.justify_content("center"),
                              css.padding_right(length.rem(1.0)),
                              css.padding_left(length.rem(1.0)),
                              css.padding_top(length.rem(0.75)),
                              css.padding_bottom(length.rem(0.75)),
                              css.min_height(length.rem(2.5)),
                              css.background(
                                "linear-gradient(135deg, rgba(38, 220, 87, 0.9), rgba(31, 180, 65, 0.9))",
                              ),
                              css.border("1px solid rgba(255, 255, 255, 0.12)"),
                              css.color("#ffffff"),
                              css.border_radius(length.px(12)),
                              css.cursor("pointer"),
                              css.font_size(length.rem(0.9)),
                              css.font_weight("600"),
                              css.letter_spacing("0.3px"),
                              css.transition(
                                "all 0.3s cubic-bezier(0.4, 0, 0.2, 1)",
                              ),
                              css.box_shadow(
                                "0 6px 20px rgba(38, 220, 87, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.25)",
                              ),
                              css.hover([
                                css.background(
                                  "linear-gradient(135deg, rgba(38, 220, 87, 1), rgba(48, 240, 100, 1))",
                                ),
                                css.transform([
                                  transform.translate_y(length.px(-3)),
                                  transform.scale(1.02, 1.08),
                                ]),
                                css.box_shadow(
                                  "0 10px 30px rgba(38, 220, 87, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.35)",
                                ),
                                css.border(
                                  "1px solid rgba(255, 255, 255, 0.25)",
                                ),
                              ]),
                              css.active([
                                css.transform([
                                  transform.translate_y(length.px(-1)),
                                ]),
                              ]),
                            ]),
                            [event.on_click(SaveDocument)],
                            [html.text("Save The File To The Room")],
                          ),
                        ],
                      ),
                      case model.tree {
                        Some(root) ->
                          element.fragment([
                            tree_view(model, root),
                            case model.filesystem_menu {
                              Some([item_id, y]) -> {
                                let y =
                                  int.parse(y) |> result.lazy_unwrap(fn() { 0 })
                                html.div(
                                  class([
                                    // css.left(length.px(x)),
                                    css.top(length.px(y)),
                                    css.position("absolute"),
                                    css.background_color("rgb(3, 29, 40)"),
                                    css.border("1px solid #e1e5e9"),
                                    css.border_radius(length.px(8)),
                                    css.box_shadow(
                                      "0 4px 12px rgba(0, 0, 0, 0.1)",
                                    ),
                                    css.padding(length.px(4)),
                                    css.min_width(length.px(180)),
                                    css.z_index(300),
                                    css.font_family(
                                      "system-ui, -apple-system, sans-serif",
                                    ),
                                    css.font_size(length.px(14)),
                                  ]),
                                  [],
                                  [
                                    html.button(
                                      class([
                                        css.display("flex"),
                                        css.align_items("center"),
                                        css.padding_left(length.px(8)),
                                        css.padding_right(length.px(12)),
                                        css.padding_top(length.px(8)),
                                        css.padding_bottom(length.px(8)),
                                        css.cursor("pointer"),
                                        css.border_radius(length.px(4)),
                                        css.border("none"),
                                        css.background_color("transparent"),
                                        css.color("#e2e8f0"),
                                        css.transition("all 0.2s ease"),
                                        css.width(length.percent(100)),
                                        css.text_align("left"),
                                        css.hover([
                                          css.background_color(
                                            "rgba(59, 130, 246, 0.1)",
                                          ),
                                          css.color("#3b82f6"),
                                        ]),
                                      ]),
                                      [event.on_click(CreateNewNote(item_id))],
                                      [
                                        html.div(
                                          class([
                                            css.width(length.px(16)),
                                            css.height(length.px(16)),
                                            css.margin_right(length.px(8)),
                                            css.display("flex"),
                                            css.align_items("center"),
                                            css.justify_content("center"),
                                          ]),
                                          [],
                                          [html.text("📄")],
                                        ),
                                        html.text("New Note"),
                                      ],
                                    ),
                                    html.button(
                                      class([
                                        css.display("flex"),
                                        css.align_items("center"),
                                        css.padding_left(length.px(8)),
                                        css.padding_right(length.px(12)),
                                        css.padding_top(length.px(8)),
                                        css.padding_bottom(length.px(8)),
                                        css.cursor("pointer"),
                                        css.border_radius(length.px(4)),
                                        css.border("none"),
                                        css.background_color("transparent"),
                                        css.color("#e2e8f0"),
                                        css.transition("all 0.2s ease"),
                                        css.width(length.percent(100)),
                                        css.text_align("left"),
                                        css.hover([
                                          css.background_color(
                                            "rgba(59, 130, 246, 0.1)",
                                          ),
                                          css.color("#3b82f6"),
                                        ]),
                                      ]),
                                      [event.on_click(CreateNewFolder(item_id))],
                                      [
                                        html.div(
                                          class([
                                            css.width(length.px(16)),
                                            css.height(length.px(16)),
                                            css.margin_right(length.px(8)),
                                            css.display("flex"),
                                            css.align_items("center"),
                                            css.justify_content("center"),
                                          ]),
                                          [],
                                          [html.text("📁")],
                                        ),
                                        html.text("New Folder"),
                                      ],
                                    ),
                                  ],
                                )
                              }
                              _ -> {
                                element.none()
                              }
                            },
                          ])
                        None -> element.none()
                      },
                    ],
                  )
                }
                False -> {
                  html.button(
                    class([
                      css.z_index(200),
                      css.position("fixed"),
                      css.display("flex"),
                      css.top(length.rem(1.5)),
                      css.right(length.rem(1.5)),
                      css.align_items("center"),
                      css.justify_content("center"),
                      css.width(length.rem(3.0)),
                      css.height(length.rem(3.0)),
                      css.background(
                        "linear-gradient(135deg, rgba(220, 38, 127, 0.9), rgba(180, 28, 100, 0.9))",
                      ),
                      css.border("2px solid rgba(255, 255, 255, 0.1)"),
                      css.color("#ffffff"),
                      css.border_radius(length.px(10)),
                      css.cursor("pointer"),
                      css.font_size(length.rem(1.2)),
                      css.font_weight("600"),
                      css.letter_spacing("1px"),
                      css.transition("all 0.3s cubic-bezier(0.4, 0, 0.2, 1)"),
                      css.box_shadow(
                        "0 4px 15px rgba(220, 38, 127, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.2)",
                      ),
                      css.hover([
                        css.background(
                          "linear-gradient(135deg, rgba(220, 38, 127, 1), rgba(240, 48, 140, 1))",
                        ),
                        css.transform([
                          transform.translate_y(length.px(-2)),
                          transform.scale(1.0, 1.05),
                        ]),
                        css.box_shadow(
                          "0 8px 25px rgba(220, 38, 127, 0.6), inset 0 1px 0 rgba(255, 255, 255, 0.3)",
                        ),
                        css.border("2px solid rgba(255, 255, 255, 0.2)"),
                      ]),
                      css.active([
                        css.transform([transform.translate_y(length.px(0))]),
                      ]),
                    ]),
                    [event.on_click(ToggleModal)],
                    [menu_svg(" #FFFFFF ")],
                  )
                }
              },
              lustre_element.unsafe_raw_html(
                "",
                "div",
                [attribute.class("editor")],
                "",
              ),
            ]
          }
          None -> {
            let button_room =
              class([
                css.background("rgba(220, 38, 127, 0.8)"),
                css.color("#ffffff"),
                css.border("none"),
                css.border_radius(length.px(8)),
                css.padding_("12px 20px"),
                // css.margin_bottom(length.px(20)),
                css.cursor("pointer"),
                css.font_weight("500"),
                css.transition("all 0.2s ease"),
                css.hover([
                  css.background("rgba(220, 38, 127, 1)"),
                  css.transform([transform.translate_y(length.px(-1))]),
                ]),
              ])

            [
              html.div(page, [], [
                case model.modal {
                  True -> {
                    html.div(
                      class([
                        css.background(
                          "linear-gradient(145deg, #1a1a2e 0%, #16213e 100%)",
                        ),
                        css.border_radius(length.px(12)),
                        css.padding_("24px"),
                        css.margin_("16px auto"),
                        css.max_width(length.px(600)),
                        css.box_shadow("0 8px 32px rgba(0, 0, 0, 0.3)"),
                        css.border("1px solid rgba(255, 255, 255, 0.1)"),
                      ]),
                      [],
                      [
                        html.button(button_room, [event.on_click(ToggleModal)], [
                          html.text("hide modal"),
                        ]),
                        model.rooms
                          |> list.filter(fn(room) {
                            !list.contains(model.selected_rooms, room.room_id)
                          })
                          |> list.map(render_room_card(_, matrix_client, "add"))
                          |> lustre_element.fragment,
                      ],
                    )
                  }

                  False -> {
                    html.button(button_room, [event.on_click(ToggleModal)], [
                      html.text("show modal"),
                    ])
                  }
                },
                html.div(class([]), [], [
                  html.h1(header_styles(), [], [
                    html.text("Your Favorite Rooms"),
                  ]),
                  case model.rooms {
                    [] -> {
                      html.div(empty_state_styles(), [], [
                        html.text("Your rooms are loading wait a sec"),
                      ])
                    }
                    _ -> {
                      html.div(container_styles(), [], [
                        model.rooms
                        |> list.filter(fn(room) {
                          model.selected_rooms
                          |> list.contains(room.room_id)
                        })
                        |> list.map(render_room_card(_, matrix_client, "remove"))
                        |> lustre_element.fragment,
                      ])
                    }
                  },
                ]),
              ]),
            ]
          }
        }
      }
    },
  )
}

fn menu_svg(color color: String) -> Element(Msg) {
  html.svg(
    class([]),
    [
      attribute.attribute("xml:space", "preserve"),
      attribute.attribute("viewBox", "0 0 297 297"),
      attribute.attribute("xmlns:xlink", "http://www.w3.org/1999/xlink"),
      attribute.attribute("xmlns", "http://www.w3.org/2000/svg"),
      attribute.id("Layer_1"),
      attribute.attribute("version", "1.1"),
      attribute.attribute("width", "30px"),
      attribute.attribute("height", "30px"),
      attribute.attribute("fill", color),
    ],
    [
      svg.g([], [
        svg.g([], [
          svg.g([], [
            svg.path([
              attribute.attribute(
                "d",
                "M279.368,24.726H102.992c-9.722,0-17.632,7.91-17.632,17.632V67.92c0,9.722,7.91,17.632,17.632,17.632h176.376
				c9.722,0,17.632-7.91,17.632-17.632V42.358C297,32.636,289.09,24.726,279.368,24.726z",
              ),
            ]),
            svg.path([
              attribute.attribute(
                "d",
                "M279.368,118.087H102.992c-9.722,0-17.632,7.91-17.632,17.632v25.562c0,9.722,7.91,17.632,17.632,17.632h176.376
				c9.722,0,17.632-7.91,17.632-17.632v-25.562C297,125.997,289.09,118.087,279.368,118.087z",
              ),
            ]),
            svg.path([
              attribute.attribute(
                "d",
                "M279.368,211.448H102.992c-9.722,0-17.632,7.91-17.632,17.633v25.561c0,9.722,7.91,17.632,17.632,17.632h176.376
				c9.722,0,17.632-7.91,17.632-17.632v-25.561C297,219.358,289.09,211.448,279.368,211.448z",
              ),
            ]),
            svg.path([
              attribute.attribute(
                "d",
                "M45.965,24.726H17.632C7.91,24.726,0,32.636,0,42.358V67.92c0,9.722,7.91,17.632,17.632,17.632h28.333
				c9.722,0,17.632-7.91,17.632-17.632V42.358C63.597,32.636,55.687,24.726,45.965,24.726z",
              ),
            ]),
            svg.path([
              attribute.attribute(
                "d",
                "M45.965,118.087H17.632C7.91,118.087,0,125.997,0,135.719v25.562c0,9.722,7.91,17.632,17.632,17.632h28.333
				c9.722,0,17.632-7.91,17.632-17.632v-25.562C63.597,125.997,55.687,118.087,45.965,118.087z",
              ),
            ]),
            svg.path([
              attribute.attribute(
                "d",
                "M45.965,211.448H17.632C7.91,211.448,0,219.358,0,229.081v25.561c0,9.722,7.91,17.632,17.632,17.632h28.333
				c9.722,0,17.632-7.91,17.632-17.632v-25.561C63.597,219.358,55.687,211.448,45.965,211.448z",
              ),
            ]),
          ]),
        ]),
      ]),
    ],
  )
}

// Styles extracted as reusable functions
fn header_styles() {
  class([
    css.font_size(length.px(32)),
    css.margin_bottom(length.px(32)),
    css.color("#ffffff"),
    css.font_weight("700"),
    css.text_align("center"),
    css.letter_spacing("-0.8px"),
    css.text_shadow("0 2px 4px rgba(0, 0, 0, 0.3)"),
  ])
}

fn room_card_styles() {
  class([
    css.display("flex"),
    css.gap(length.px(16)),
    css.align_items("center"),
    css.padding_("20px 24px"),
    css.margin_bottom(length.px(16)),
    css.background("rgba(255, 255, 255, 0.08)"),
    css.border_radius(length.px(12)),
    css.border("1px solid rgba(255, 255, 255, 0.12)"),
    css.backdrop_filter("blur(10px)"),
    css.transition("all 0.3s cubic-bezier(0.4, 0, 0.2, 1)"),
    css.hover([
      css.background("rgba(255, 255, 255, 0.12)"),
      css.border_color("rgba(255, 255, 255, 0.2)"),
      css.transform([transform.translate_y(length.px(-3))]),
      css.box_shadow("0 12px 32px rgba(0, 0, 0, 0.25)"),
    ]),
  ])
}

fn enter_button_styles() {
  class([
    css.background("rgba(220, 38, 127, 0.8)"),
    css.color("#ffffff"),
    css.border("none"),
    css.border_radius(length.px(10)),
    css.padding_("14px 24px"),
    css.cursor("pointer"),
    css.flex_grow(1),
    css.font_weight("600"),
    css.font_size(length.px(16)),
    css.letter_spacing("0.025em"),
    css.transition("all 0.2s cubic-bezier(0.4, 0, 0.2, 1)"),
    css.box_shadow("0 4px 14px rgba(99, 102, 241, 0.35)"),
    css.hover([
      css.transform([transform.translate_y(length.px(-2))]),
      css.background("rgba(220, 38, 127, 1)"),
      css.transform([transform.translate_y(length.px(-1))]),
    ]),
    css.active([css.transform([transform.translate_y(length.px(0))])]),
  ])
}

fn remove_button_styles() {
  class([
    css.background("rgba(248, 113, 113, 0.15)"),
    css.color("#f87171"),
    css.border("1px solid rgba(248, 113, 113, 0.25)"),
    css.border_radius(length.px(10)),
    css.padding_("14px 20px"),
    css.cursor("pointer"),
    css.font_size(length.px(14)),
    css.font_weight("600"),
    css.letter_spacing("0.025em"),
    css.transition("all 0.2s cubic-bezier(0.4, 0, 0.2, 1)"),
    css.hover([
      css.background("rgba(248, 113, 113, 0.25)"),
      css.color("#ffffff"),
      css.border_color("rgba(248, 113, 113, 0.4)"),
      css.transform([transform.translate_y(length.px(-2))]),
      css.box_shadow("0 4px 12px rgba(248, 113, 113, 0.3)"),
    ]),
    css.active([css.transform([transform.translate_y(length.px(0))])]),
  ])
}

fn add_button_styles() {
  class([
    css.background("rgba(113, 248, 115, 0.15)"),
    css.color("rgb(118, 248, 113)"),
    css.border("1px solid rgba(113, 248, 129, 0.25)"),
    css.border_radius(length.px(10)),
    css.padding_("14px 20px"),
    css.cursor("pointer"),
    css.font_size(length.px(14)),
    css.font_weight("600"),
    css.letter_spacing("0.025em"),
    css.transition("all 0.2s cubic-bezier(0.4, 0, 0.2, 1)"),
    css.hover([
      css.background("rgba(133, 248, 113, 0.25)"),
      css.color("#ffffff"),
      css.border_color("rgba(113, 248, 124, 0.4)"),
      css.transform([transform.translate_y(length.px(-2))]),
      css.box_shadow("0 4px 12px rgba(113, 248, 151, 0.3)"),
    ]),
    css.active([css.transform([transform.translate_y(length.px(0))])]),
  ])
}

fn container_styles() {
  class([
    css.display("flex"),
    css.flex_direction("column"),
    css.gap(length.px(0)),
    // Remove gap since we're using margin-bottom on cards
  ])
}

fn empty_state_styles() {
  class([
    css.text_align("center"),
    css.padding_("40px 20px"),
    css.color("rgba(255, 255, 255, 0.6)"),
    css.font_size(length.px(16)),
  ])
}

fn render_room_card(room: Room, matrix_client: MatrixClient, message: String) {
  html.div(room_card_styles(), [], [
    html.button(
      enter_button_styles(),
      [event.on_click(EnterRoom(room.room_id, matrix_client))],
      [html.text(room.name)],
    ),
    case message {
      "add" -> {
        html.button(
          add_button_styles(),
          [event.on_click(AddRoom(room.room_id))],
          [html.text("Add")],
        )
      }
      "remove" -> {
        html.button(
          remove_button_styles(),
          [event.on_click(RemoveRoom(room.room_id))],
          [html.text("Remove")],
        )
      }

      _ -> {
        element.none()
      }
    },
  ])
}

fn add_room(room_id: String) {
  use dispatch <- effect.from
  let assert Ok(localstorage) = local()
  let rooms = storage.get_item(localstorage, "rooms")

  case rooms {
    Ok(json_string) -> {
      let room_decoder = {
        use room_ids <- decode.field("room_ids", decode.list(decode.string))

        decode.success(room_ids)
      }

      case json.parse(from: json_string, using: room_decoder) {
        Ok(selected_rooms) -> {
          let rooms = selected_rooms |> list.append([room_id])

          let json =
            json.object([#("room_ids", json.array(rooms, json.string))])
            |> json.to_string

          let _ = storage.set_item(localstorage, "rooms", json)

          dispatch(DisplaySelectedRooms(rooms))
        }
        Error(_) -> {
          let json =
            json.object([#("room_ids", json.array([room_id], json.string))])
            |> json.to_string

          let _ = storage.set_item(localstorage, "rooms", json)

          dispatch(DisplaySelectedRooms([room_id]))
        }
      }
    }

    Error(_) -> {
      let json =
        json.object([#("room_ids", json.array([room_id], json.string))])
        |> json.to_string

      let _ = storage.set_item(localstorage, "rooms", json)

      dispatch(DisplaySelectedRooms([room_id]))
    }
  }
}

fn remove_room(room_id: String) {
  use dispatch <- effect.from
  let assert Ok(localstorage) = local()
  let rooms = storage.get_item(localstorage, "rooms")

  case rooms {
    Ok(json_string) -> {
      let room_decoder = {
        use room_ids <- decode.field("room_ids", decode.list(decode.string))

        decode.success(room_ids)
      }

      case json.parse(from: json_string, using: room_decoder) {
        Ok(selected_rooms) -> {
          let rooms =
            selected_rooms
            |> list.filter(fn(room) { room != room_id })
          let json =
            json.object([#("room_ids", json.array(rooms, json.string))])
            |> json.to_string

          let _ = storage.set_item(localstorage, "rooms", json)

          dispatch(DisplaySelectedRooms(rooms))
        }
        Error(_) -> {
          dispatch(DisplayErrorToast("couldn't find any stored rooms"))
        }
      }
    }

    Error(_) -> {
      dispatch(DisplayErrorToast("couldn't find any stored rooms"))
    }
  }
}

fn login() {
  let assert Ok(localstorage) = local()

  let access_token = get_item(localstorage, "access_token")
  let device_id = get_item(localstorage, "device_id")
  let user_id = get_item(localstorage, "user_id")

  case access_token {
    Ok(access_token) -> {
      case device_id {
        Ok(device_id) -> {
          case user_id {
            Ok(user_id) -> {
              // let _ = login_matrix(access_token, user_id, device_id)

              login_matrix(access_token, user_id, device_id)
            }
            Error(_) -> {
              reset_app()
              get_login_sso()
            }
          }
        }
        Error(_) -> {
          reset_app()
          get_login_sso()
        }
      }
    }
    Error(_) -> {
      reset_app()
      get_login_sso()
    }
  }
}

type MatrixClient

@external(javascript, "./js/editor.ts", "user_selected_note")
fn do_user_selected_note(item_id: String) -> Nil

fn user_selected_note(item_id) -> Effect(Msg) {
  use _ <- effect.from
  do_user_selected_note(item_id)
}

fn create_new_note(loro_doc: LoroDoc, item_id: String) -> Effect(Msg) {
  use _ <- effect.from
  do_create_new_note(loro_doc, item_id)
}

@external(javascript, "./js/editor.ts", "create_new_note")
fn do_create_new_note(loro_doc: LoroDoc, item_id: String) -> Nil

fn create_new_folder(loro_doc: LoroDoc, item_id) -> Effect(Msg) {
  use _ <- effect.from
  do_create_new_folder(loro_doc, item_id)
}

@external(javascript, "./js/editor.ts", "create_new_folder")
fn do_create_new_folder(loro_doc: LoroDoc, item_id: String) -> Nil

fn change_item_name(loro_doc: LoroDoc, item_id, item_name) -> Effect(Msg) {
  use dispatch <- effect.from

  do_change_item_name(loro_doc, item_id, item_name, fn() {
    dispatch(UserCanceledEditingItem)
  })
}

fn delete_item(loro_doc: LoroDoc, item: String) -> Effect(Msg) {
  use _ <- effect.from

  do_delete_item(loro_doc, item)
}

fn move_item(loro_doc: LoroDoc, item: String, folder: String) -> Effect(Msg) {
  use _ <- effect.from

  do_move_item(loro_doc, item, folder)
}

@external(javascript, "./js/editor.ts", "save_document")
fn do_save_document() -> Nil

fn save_document() {
  use _ <- effect.from
  do_save_document()
}

@external(javascript, "./js/editor.ts", "login_matrix")
fn do_login_matrix(
  access_token: String,
  user_id: String,
  device_id: String,
) -> Promise(Result(MatrixClient, String))

fn login_matrix(access_token: String, user_id: String, device_id: String) {
  use dispatch <- effect.from

  do_login_matrix(access_token, user_id, device_id)
  |> promise.tap(fn(result) {
    case result {
      Ok(matrix_client) -> {
        dispatch(UserHasLoggedIn(matrix_client))
      }
      Error(msg) -> {
        reset_app()
        dispatch(DisplayErrorToast(msg))

        Nil
      }
    }
  })
  Nil
}

@external(javascript, "./js/editor.ts", "init_tiptap")
fn do_init_tiptap(
  loro_doc: LoroDoc,
  matrix_client: MatrixClient,
  room_id: String,
) -> Nil

fn init_tiptap(matrix_client: MatrixClient, room_id: String) {
  use dispatch, _ <- effect.after_paint

  let loro_doc = create_loro_doc(room_id)
  dispatch(LoroDocCreated(loro_doc))

  get_tree(loro_doc, fn(tree) {
    let results = json.parse(from: tree, using: node_decoder())

    case results {
      Ok(root) -> {
        dispatch(RenderTree(root))
      }
      Error(error) -> {
        echo error
        Nil
      }
    }
  })

  do_init_tiptap(loro_doc, matrix_client, room_id)
}

fn delete_items(localstorage: storage.Storage) {
  remove_item(localstorage, "access_token")
  remove_item(localstorage, "device_id")
  remove_item(localstorage, "user_id")
}

fn reset_app() {
  let assert Ok(localstorage) = local()

  delete_items(localstorage)
}

// UPDATE ----------------------------------------------------------------------

@external(javascript, "./js/editor.ts", "login_sso")
fn do_login_sso() -> Nil

fn login_sso() {
  use _ <- effect.from
  do_login_sso()
}

@external(javascript, "./js/editor.ts", "get_login_sso")
fn do_get_login_sso() -> Promise(Result(MatrixClient, String))

fn get_login_sso() {
  use dispatch <- effect.from

  do_get_login_sso()
  |> promise.tap(fn(result) {
    case result {
      Ok(matrix_client) -> {
        dispatch(UserHasLoggedIn(matrix_client))
      }
      Error(error_message) -> {
        case error_message {
          "" -> {
            Nil
          }
          _ -> {
            reset_app()
            dispatch(DisplayErrorToast(error_message))
          }
        }

        Nil
      }
    }
  })
  Nil
}

@external(javascript, "./js/editor.ts", "get_rooms")
fn do_get_rooms(matrix_client: MatrixClient) -> Nil

fn get_rooms(matrix_client: MatrixClient) {
  use dispatch <- effect.from
  do_get_rooms(matrix_client)

  let assert Ok(localstorage) = local()
  let rooms = storage.get_item(localstorage, "rooms")

  case rooms {
    Ok(json_string) -> {
      let room_decoder = {
        use room_ids <- decode.field("room_ids", decode.list(decode.string))

        decode.success(room_ids)
      }

      case json.parse(from: json_string, using: room_decoder) {
        Ok(selected_rooms) -> {
          dispatch(DisplaySelectedRooms(selected_rooms))
        }
        Error(_) -> {
          Nil
        }
      }
    }

    Error(_) -> {
      Nil
    }
  }
}

fn success_toast(content: String) {
  toast.options()
  |> toast.level(level.Success)
  |> toast.custom(content)
}

fn error_toast(content) {
  toast.options()
  |> toast.timeout(10_000)
  |> toast.level(level.Error)
  |> toast.custom(content)
}

// VIEW ------------------------------------------------------------------------
type Room {
  Room(name: String, room_id: String)
}

pub type TreeItemType {
  Folder
  File
}

pub type TreeItem {
  TreeItem(
    id: String,
    name: String,
    item_type: TreeItemType,
    children: List(TreeItem),
  )
}

fn get_item_class(item_type: String) -> String {
  case item_type {
    "folder" -> "tree-item tree-folder"
    "file" -> "tree-item tree-file"
    _ -> panic
  }
}

fn get_expand_icon(item_type: String, is_expanded: Bool) -> String {
  case item_type {
    "folder" ->
      case is_expanded {
        True -> "▼"
        False -> "▶"
      }
    "file" -> ""
    _ -> panic
  }
}

fn get_item_icon(item_type: String) -> String {
  case item_type {
    "folder" -> "📁"
    "file" -> "📄"
    _ -> panic
  }
}

// View functions
fn tree_item_view(
  is_root: Bool,
  item item: Node,
  model model: Model,
) -> Element(Msg) {
  let is_dragged = {
    case model.dragged_over_tree_item {
      Some(item_id) -> {
        item_id == item.id
      }
      None -> False
    }
  }

  let assert Ok(item_type_value) = item.meta |> dict.get("item_type")
  let assert Ok(item_type) = decode.run(item_type_value, decode.string)

  let name_value = item.meta |> dict.get("name")
  let name = {
    case name_value {
      Ok(name_value) -> {
        case decode.run(name_value, decode.string) {
          Ok(name) -> name
          Error(_) -> "Untitled"
        }
      }
      Error(_) -> "Untitled"
    }
  }

  let tree_item_classes = [
    attribute.classes([
      #(get_item_class(item_type), True),
      #("drop-target", is_dragged),
    ]),
    attribute.data("item_type", item_type),
    attribute.data("drag_id", item.id),
    case item.parent {
      Some(parent_id) -> attribute.data("parent_id", parent_id)
      None -> attribute.none()
    },
    // event.on_click(HideFileSystemMenu),
    case item_type {
      "folder" -> {
        event.on("click", {
          use y <- decode.field("clientY", decode.int)

          let y = int.to_string(y)

          decode.success(DisplayFileSystemMenu(item.id, y))
        })
      }
      "file" -> {
        event.on_click(UserSelectedNote(item.id))
      }
      _ -> attribute.none()
    },
  ]

  let file_system_menu_handler = case item_type {
    "folder" -> {
      event.stop_propagation(
        event.on("click", {
          use y <- decode.field("clientY", decode.int)
          let y = int.to_string(y)

          decode.success(DisplayFileSystemMenu(item.id, y))
        }),
      )
    }
    "file" -> {
      case item.parent {
        Some(parent_id) -> {
          event.stop_propagation(
            event.on("click", {
              use y <- decode.field("clientY", decode.int)

              let y = int.to_string(y)

              decode.success(DisplayFileSystemMenu(parent_id, y))
            }),
          )
        }
        None -> attribute.none()
      }
    }
    _ -> attribute.none()
  }

  html.div(
    class([]),
    case is_root {
      True -> {
        tree_item_classes
        |> list.append([
          attribute.class("root-node"),
          attribute.draggable(False),
          event.on("click", {
            use y <- decode.field("clientY", decode.int)

            let y = int.to_string(y)

            decode.success(DisplayFileSystemMenu(item.id, y))
          }),
        ])
      }
      False -> tree_item_classes
    },
    case is_root {
      True -> []

      False -> {
        [
          case item_type {
            "folder" -> {
              case item.children {
                [] -> element.none()
                _ -> {
                  html.span(
                    class([]),
                    [
                      event.stop_propagation(
                        event.on_click(ToggleFolderExpanded(item.id)),
                      ),
                      attribute.class("expand-icon"),
                    ],
                    [
                      html.text(get_expand_icon(
                        item_type,
                        model.expanded_folders |> list.contains(item.id),
                      )),
                    ],
                  )
                }
              }
            }
            "file" -> {
              element.none()
            }
            _ -> {
              element.none()
            }
          },
          html.span(class([]), [attribute.class("tree-icon")], [
            html.text(get_item_icon(item_type)),
          ]),
          {
            let default_item =
              html.span(class([]), [attribute.class("tree-name")], [
                html.text(name),
              ])

            case model.edited_tree_item {
              Some(item_id) -> {
                case item_id == item.id {
                  True -> {
                    html.input(class([]), [
                      attribute.class("tree-name"),
                      case model.selected_item_name {
                        Some(value) -> {
                          attribute.value(value)
                        }
                        None -> {
                          attribute.value(name)
                        }
                      },
                      event.on_input(ItemNameHasChanged),
                    ])
                  }
                  False -> {
                    default_item
                  }
                }
              }
              None -> {
                default_item
              }
            }
          },
          case model.edited_tree_item {
            Some(item_id) -> {
              case item_id == item.id {
                True -> {
                  element.fragment([
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(
                          event.on_click(UserFinishedEditingItem(item.id)),
                        ),
                      ],
                      [html.text("✅")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(event.on_click(
                          UserCanceledEditingItem,
                        )),
                      ],
                      [html.text("❌")],
                    ),
                  ])
                }
                False ->
                  element.fragment([
                    html.button(
                      class([]),
                      [attribute.class("edit-button"), file_system_menu_handler],
                      [html.text("➕")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(
                          event.on_click(UserEditingItem(item.id)),
                        ),
                      ],
                      [html.text("✏️")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(
                          event.on_click(DeleteItem(item.id)),
                        ),
                      ],
                      [html.text("🗑️")],
                    ),
                  ])
              }
            }
            None ->
              element.fragment([
                html.button(
                  class([]),
                  [attribute.class("edit-button"), file_system_menu_handler],
                  [html.text("➕")],
                ),
                html.button(
                  class([]),
                  [
                    attribute.class("edit-button"),
                    event.stop_propagation(
                      event.on_click(UserEditingItem(item.id)),
                    ),
                  ],
                  [html.text("✏️")],
                ),
                html.button(
                  class([]),
                  [
                    attribute.class("edit-button"),
                    event.stop_propagation(event.on_click(DeleteItem(item.id))),
                  ],
                  [html.text("🗑️")],
                ),
              ])
          },
        ]
      }
    },
  )
}

fn tree_children_view(
  is_item_at_root: Bool,
  children: List(Node),
  model: Model,
) -> Element(Msg) {
  let get_item_info = fn(item: Node) {
    let assert Ok(type_value) = item.meta |> dict.get("item_type")
    let assert Ok(item_type) = decode.run(type_value, decode.string)

    let name = case item.meta |> dict.get("name") {
      Ok(value) -> {
        let assert Ok(name) = decode.run(value, decode.string)
        Some(name)
      }
      Error(_) -> None
    }

    #(item_type, name)
  }

  html.div(
    class([]),
    [
      case is_item_at_root {
        True -> {
          attribute.none()
        }
        False -> {
          attribute.class("tree-children")
        }
      },
    ],
    children
      |> list.sort(fn(a, b) {
        let #(a_type, a_name) = get_item_info(a)
        let #(b_type, b_name) = get_item_info(b)

        case a_type, b_type {
          "folder", "file" -> order.Lt
          "file", "folder" -> order.Gt
          _, _ -> {
            case a_name, b_name {
              Some(name_a), Some(name_b) -> string.compare(name_a, name_b)
              Some(_), None -> order.Lt
              // Some values come before None
              None, Some(_) -> order.Gt
              // None comes after Some values
              None, None -> order.Eq
              // Both None are equal
            }
          }
        }
      })
      |> list.map(fn(child) {
        let #(item_type, _) = get_item_info(child)

        case item_type {
          "folder" -> {
            [
              tree_item_view(False, child, model),
              case child.children {
                [] -> element.none()
                _ -> {
                  case model.expanded_folders |> list.contains(child.id) {
                    True -> tree_children_view(False, child.children, model)
                    False -> element.none()
                  }
                }
              },
            ]
          }
          "file" -> [tree_item_view(False, child, model)]
          _ -> panic
        }
      })
      |> list.flatten,
  )
}

fn tree_view(model: Model, tree: Node) -> Element(Msg) {
  html.div(class([]), [attribute.class("tree")], [
    case tree.children {
      [] -> element.none()
      _ -> tree_children_view(True, tree.children, model)
    },
    tree_item_view(True, tree, model),
  ])
}
