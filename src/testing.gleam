import gleam/dynamic/decode
import gleam/int
import gleam/order
import gleam/result
import gleam/string
import lustre/event
import sketch/css/length

import gleam/javascript/array
import gleam/list
import gleam/option.{type Option, None, Some}

import grille_pain
import plinth/browser/document
import plinth/browser/element as browser_element

import lustre
import lustre/attribute
import lustre/effect.{type Effect}

// import lustre/element/keyed as lustre_keyed

import gleam/dict.{type Dict}
import gleam/json
import sketch
import sketch/css.{class}

import sketch/lustre as sketch_lustre
import sketch/lustre/element.{type Element}
import sketch/lustre/element/html

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
      Model(False, None, None, None, None, None, None, []),
    )

  Nil
}

// MODEL -----------------------------------------------------------------------
type Model {
  Model(
    modal: Bool,
    filesystem_menu: Option(List(String)),
    loro_doc: Option(LoroDoc),
    tree: Option(Node),
    dragged_over_tree_item: Option(String),
    edited_tree_item: Option(String),
    item_name: Option(String),
    expanded_folders: List(String),
  )
}

type LoroDoc

fn init(model: Model) -> #(Model, Effect(Msg)) {
  #(model, create_tree())
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
fn create_loro_doc() -> LoroDoc

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
  use children <- decode.field("children", decode.list(node_decoder()))

  decode.success(Node(
    id: id,
    parent: parent,
    index: index,
    meta: meta,
    children: children,
  ))
}

// pub fn root_decoder() {
//   use id <- decode.field("id", decode.string)
//   use index <- decode.field("index", decode.int)
//   use fractional_index <- decode.field("fractionalIndex", decode.string)
//   use meta <- decode.field("meta", decode.dict(decode.string, decode.dynamic))
//   use children <- decode.field("children", decode.list(node_decoder()))
//   decode.success(Node(
//     id: id,
//     index: index,
//     parent: None,
//     fractional_index: fractional_index,
//     meta: meta,
//     children: children,
//   ))
// }

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

fn create_tree() {
  use dispatch, _ <- effect.after_paint

  let loro_doc = create_loro_doc()
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

  Nil
}

pub opaque type Msg {
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
  DisplayFileSystemMenu(String, String, String)
  CreateNewNote(String)
  CreateNewFolder(String)
  HideFileSystemMenu
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    DoNothing -> #(model, effect.none())
    HideFileSystemMenu -> {
      #(Model(..model, filesystem_menu: None), effect.none())
    }
    DisplayFileSystemMenu(item_id, x, y) -> {
      #(Model(..model, filesystem_menu: Some([item_id, x, y])), effect.none())
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
      Model(..model, item_name: None, edited_tree_item: None),
      effect.none(),
    )

    ToggleFolderExpanded(folder_id) -> {
      let folder_id_list = model.expanded_folders

      case folder_id_list |> list.contains(folder_id) {
        True -> {
          let expanded_folders =
            folder_id_list |> list.filter(fn(id) { id != folder_id })
          #(Model(..model, expanded_folders:), init_dnd())
        }
        False -> {
          let expanded_folders = folder_id_list |> list.append([folder_id])
          #(Model(..model, expanded_folders:), init_dnd())
        }
      }
    }

    ItemNameHasChanged(name) -> {
      #(Model(..model, item_name: Some(name)), effect.none())
    }

    UserEditingItem(item_id) -> #(
      Model(..model, edited_tree_item: Some(item_id)),
      effect.none(),
    )

    UserFinishedEditingItem(item_id) -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          case model.item_name {
            Some(item_name) -> {
              let trimmed_name = item_name |> string.trim()
              #(
                Model(..model, item_name: None),
                change_item_name(loro_doc, item_id, trimmed_name),
              )
            }
            None -> #(
              Model(..model, item_name: None, edited_tree_item: None),
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
  }
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

fn view(model: Model, stylesheet) -> Element(Msg) {
  use <- sketch_lustre.render(stylesheet:, in: [sketch_lustre.node()])
  case model.tree {
    Some(root) ->
      html.div(class([]), [attribute.id("main-app")], [
        tree_view(model, root),
        case model.filesystem_menu {
          Some([item_id, x, y]) -> {
            let x = int.parse(x) |> result.lazy_unwrap(fn() { 0 })
            let y = int.parse(y) |> result.lazy_unwrap(fn() { 0 })
            html.div(
              class([
                css.left(length.px(x)),
                css.top(length.px(y)),
                css.position("absolute"),
                css.background_color("rgb(3, 29, 40)"),
                css.border("1px solid #e1e5e9"),
                css.border_radius(length.px(8)),
                css.box_shadow("0 4px 12px rgba(0, 0, 0, 0.1)"),
                css.padding(length.px(4)),
                css.min_width(length.px(180)),
                css.z_index(1000),
                css.font_family("system-ui, -apple-system, sans-serif"),
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
                      css.background_color("rgba(59, 130, 246, 0.1)"),
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
                      css.background_color("rgba(59, 130, 246, 0.1)"),
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
  }
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

  
  ]

  let file_system_menu_handler = case item_type {
    "folder" -> {
      event.prevent_default(
        event.on("click", {
          use x <- decode.field("clientX", decode.int)
          use y <- decode.field("clientY", decode.int)

          let x = int.to_string(x)
          let y = int.to_string(y)

          decode.success(DisplayFileSystemMenu(item.id, x, y))
        }),
      )
    }
    "file" -> {
      case item.parent {
        Some(parent_id) -> {
          event.prevent_default(
            event.on("click", {
              use x <- decode.field("clientX", decode.int)
              use y <- decode.field("clientY", decode.int)

              let x = int.to_string(x)
              let y = int.to_string(y)

              decode.success(DisplayFileSystemMenu(parent_id, x, y))
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
            use x <- decode.field("clientX", decode.int)
            use y <- decode.field("clientY", decode.int)
            let x = int.to_string(x)
            let y = int.to_string(y)

            decode.success(DisplayFileSystemMenu(item.id, x, y))
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
                      event.on_click(ToggleFolderExpanded(item.id)),
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
          case model.edited_tree_item {
            Some(item_id) -> {
              case item_id == item.id {
                True -> {
                  html.input(class([]), [
                    attribute.class("tree-name"),
                    case model.item_name {
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
                  html.span(
                    class([]),
                    [
                      attribute.class("tree-name"),
                      case item_type {
                        "folder" -> {
                          event.on("click", {
                            use x <- decode.field("clientX", decode.int)
                            use y <- decode.field("clientY", decode.int)

                            let x = int.to_string(x)
                            let y = int.to_string(y)

                            decode.success(DisplayFileSystemMenu(item.id, x, y))
                          })
                        }
                        "file" -> {
                          case item.parent {
                            Some(parent_id) -> {
                              event.on("click", {
                                use x <- decode.field("clientX", decode.int)
                                use y <- decode.field("clientY", decode.int)

                                let x = int.to_string(x)
                                let y = int.to_string(y)

                                decode.success(DisplayFileSystemMenu(
                                  parent_id,
                                  x,
                                  y,
                                ))
                              })
                            }
                            None -> attribute.none()
                          }
                        }
                        _ -> attribute.none()
                      },
                    ],
                    [html.text(name)],
                  )
                }
              }
            }
            None -> {
              html.span(class([]), [attribute.class("tree-name")], [
                html.text(name),
              ])
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
                        event.on_click(UserFinishedEditingItem(item.id)),
                      ],
                      [html.text("✅")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.on_click(UserCanceledEditingItem),
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
                        event.on_click(UserEditingItem(item.id)),
                      ],
                      [html.text("✏️")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.on_click(DeleteItem(item.id)),
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
                    event.on_click(UserEditingItem(item.id)),
                  ],
                  [html.text("✏️")],
                ),
                html.button(
                  class([]),
                  [
                    attribute.class("edit-button"),
                    event.on_click(DeleteItem(item.id)),
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
