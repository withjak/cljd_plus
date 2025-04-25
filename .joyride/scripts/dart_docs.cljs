(ns dart-docs
  (:require [clojure.walk :refer [keywordize-keys]]
            ["fs" :as fs]
            [clojure.string :as string]))

(defn read-json-sync [file-path]
  (-> (.readFileSync fs file-path "utf8")
      (js/JSON.parse)
      (js->clj)
      (keywordize-keys)))

(defn format-widdart-docs->markdown [widget-name widget-info]
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

(defonce widgets-data
  (->> "/tmp/cljd_flutter_widget_docs.json"
       read-json-sync
       (map (fn [[k v]]
              [k (format-widdart-docs->markdown (name k) v)]))
       (into {})))
