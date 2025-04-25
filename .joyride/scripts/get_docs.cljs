(ns get-docs
  (:require ["child_process" :as cp]
            ["path" :as node-path]
            [clojure.walk :refer [keywordize-keys]]
            ["fs" :as fs]
            [clojure.string :as string]
            ))

(defn read-json-sync [file-path]
  (-> (.readFileSync fs file-path "utf8")
      (js/JSON.parse)
      (js->clj)
      (keywordize-keys)))

(defn format-widget-docs->markdown [widget-name widget-info]
  (when widget-info
    (let [class-doc         (:classDoc widget-info "*No documentation found for widget.*\n")
          constructors      (:constructors widget-info [])
          constructors_json (:constructors_json widget-info [])
          markdown-parts    [(str "## " widget-name "\n\n")
                             (str class-doc "\n")]]
      
      (if (seq constructors)
        (let [contruct-signature (fn [ctor]
                                   (let [signature (:signature ctor "")
                                         ctor-doc  (:documentation ctor "*No documentation found for this constructor.*\n")]
                                     [(str "```dart\n" signature "\n```\n\n")
                                      (str ctor-doc "\n")
                                      "---\n"]))
              doc                (->> constructors
                                      (map contruct-signature)
                                      (apply concat)
                                      (into (conj markdown-parts "\n### Constructors\n\n"))
                                      (string/join "\n"))]
          {:doc               doc
           :constructors_json constructors_json})
        {:doc               (string/join "\n" markdown-parts)
         :constructors_json constructors_json}))))


#_
(defn extract-directory-path [file-path]
  (when (not= "" file-path)
    (node-path/dirname file-path)))

#_
(defn get-flutter-widget-doc [script-path project-path]
  (try
    (let [script-dir (extract-directory-path script-path)]
      (if script-dir
        (let [result (cp/spawnSync "dart"
                                   #js ["run" script-path "--project-path" project-path]
                                   #js {:cwd      script-dir
                                        :encoding "utf8"
                                        :timeout  600000 ; 5 seconds
                                        :shell    false})]
          ;; Check the exit status code
          (if (zero? (.-status result))
            ;; --- Success ---
            {:status :success
             :stdout (.-stdout result)}
            ;; --- Failure ---
            {:status    :error
             :exit-code (.-status result)
             :stderr    (.-stderr result)
             :stdout    (.-stdout result)}))
        ;; --- Error: Could not determine script directory ---
        {:status      :error
         :message     "Could not determine script directory from path."
         :script-path script-path}))
    (catch js/Error e
      ;; --- Error: Exception during spawn ---
      {:status  :exception
       :message (.-message e)
       :error   e})))

