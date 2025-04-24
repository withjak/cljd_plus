(ns workspace-activate
  (:require [joyride.core :as joyride]
            ["vscode" :as vscode] 
            [autocomplete :as ac]
            [cljd-widget-hover :as cwh]))
 ;; For output channel or logging

(defn handle-selection-change [event]
  (let [editor   (.-textEditor event)
        document (.-document editor)
        ;; Use the primary selection's active position
        position (-> editor .-selection .-active)]

    ;; Check if it's a Clojure document (adjust language ID if needed)
    (when (= "clojure" (.-languageId document))
      (if-let [form-range (ac/get-enclosing-form-range document position)]
        ;; Log to the Joyride output channel for demonstration
        ;; Avoid using showInformationMessage here as it's too intrusive for every cursor move.
        (let [output (joyride/output-channel)
              start-line (.-line (.-start form-range))
              start-char (.-character (.-start form-range))
              end-line   (.-line (.-end form-range))
              end-char   (.-character (.-end form-range))]
          (.appendLine output (str "Cursor moved. Enclosing form range: ["
                                   start-line ":" start-char " -> "
                                   end-line ":" end-char "]")))
        ;; Optional: Handle case where no form is found at the position
        #_(let [output (joyride/output-channel)]
            (.appendLine output (str "Cursor moved. No enclosing form found at position.")))))))

(defonce !db (atom {:disposables []}))

;; To make the activation script re-runnable we dispose of
;; event handlers and such that we might have registered
;; in previous runs.
(defn- clear-disposables! []
  (run! (fn [disposable]
          (.dispose disposable))
        (:disposables @!db))
  (swap! !db assoc :disposables []))

;; Pushing the disposables on the extension context's
;; subscriptions will make VS Code dispose of them when the
;; Joyride extension is deactivated.
(defn- push-disposable [disposable]
  (swap! !db update :disposables conj disposable)
  (-> (joyride/extension-context)
      .-subscriptions
      (.push disposable)))

(defn- my-main []
  (println "Hello World, from my-main workspace_activate.cljs script")
  (clear-disposables!)
  
  (push-disposable
   ;; It might surprise you to see how often and when this happens,
   ;; and when it doesn't happen.
   (vscode/workspace.onDidOpenTextDocument
    (fn [doc]
      (println "[Joyride example]"
               (.-languageId doc)
               "document opened:"
               (.-fileName doc))))) 
  
  (push-disposable 
   (cwh/register-cljd-widget-provider!))
  (push-disposable 
   (vscode/window.onDidChangeTextEditorSelection handle-selection-change)))

(when (= (joyride/invoked-script) joyride/*file*)
  (my-main))

(comment 
  (do
    (clear-disposables!)
    (my-main)))