import ReactDOM from "react-dom/client";
import "@blocknote/core/fonts/inter.css";
import { BlockNoteView } from "@blocknote/mantine";
import "@blocknote/mantine/style.css";
import { useCreateBlockNote } from "@blocknote/react";
import React, { useEffect, useRef } from "react";

function Editor({ extension, onEditorReady }) {
  const editor = useCreateBlockNote({
    _tiptapOptions: {
      extensions: [extension] 
    }
  });

  useEffect(() => {
    if (onEditorReady && editor._tiptapEditor) {
      onEditorReady(editor._tiptapEditor,editor);
    }
  }, [editor, onEditorReady]);

  return <BlockNoteView editor={editor} />;
}


let rootInstance ;

export function render_editor(extensions, callback) {
  const container = document.querySelector(".editor");
  

  if (rootInstance) {
    rootInstance.unmount();
    rootInstance = null;
  }

  rootInstance = ReactDOM.createRoot(container!);

  rootInstance.render(
    <Editor extension={extensions} onEditorReady={callback} />
  );
}