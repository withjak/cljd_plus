(ns get-docs
  (:require ["child_process" :as cp]
            ["path" :as node-path]
            [clojure.walk :refer [keywordize-keys]]
            ["fs" :as fs]
            [clojure.string :as str]
            ))

(defn read-json-sync [file-path]
  (-> (.readFileSync fs file-path "utf8")
      (js/JSON.parse)
      (js->clj)
      (keywordize-keys)))

(defn format-widget-docs->markdown [widget-name widget-info]
  (when widget-info
    (let [class-doc (:classDoc widget-info "") ;; Get class doc, default to empty string
          constructors (:constructors widget-info []) ;; Get constructors list
          markdown-parts [(str "## " widget-name "\n\n") ;; Add H2 Heading
                          (if (not (str/blank? class-doc))
                            (str class-doc "\n")
                            "*No documentation found for widget.*\n")]]

      ;; Add Constructors section if any exist
      (if (seq constructors)
        (->> constructors
             (map (fn [ctor]
                    (let [signature (:signature ctor "")
                          ctor-doc (:documentation ctor "")]
                      [(str "```dart\n" signature "\n```\n\n") ;; Code fence for signature
                       (if (not (str/blank? ctor-doc))
                         (str ctor-doc "\n")
                         "*No documentation found for this constructor.*\n")
                       "---\n"]))) ;; Separator
             (apply concat) ;; Flatten the list of parts for constructors
             (into (conj markdown-parts "\n### Constructors\n\n")) ;; Add H3 heading and combine parts
             (str/join "\n")) ;; Join all parts into a single string
        ;; If no constructors, just join the heading and class doc
        (str/join "\n" markdown-parts)))))


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

