(ns autocomplete ;; Choose an appropriate namespace
  (:require ["vscode" :as vscode]
            [rewrite-clj.zip :as z] 
            [utils]
            [dart-docs]))

(defn- vscode->rewrite-pos 
  [position]
  ;; VS Code is 0-based, rewrite-clj is 1-based
  {:line (inc (.-line position))
   :char (inc (.-character position))})

(defn get-enclosing-form-fn-name
  [document position]
  (try
    (let [text        (.getText document)
          rewrite-pos (vscode->rewrite-pos position)
          when-not-list-stop (fn [zloc] 
                               (when (z/list? zloc)
                                 zloc))]
      (-> text
          (z/of-string {:track-position? true})
          (z/find-last-by-pos {:row (:line rewrite-pos)
                               :col (:char rewrite-pos)} 
                              z/seq?)
          when-not-list-stop 
          z/down
          z/string)) 
    
    (catch :default e
      (println (str "Error parsing file '" (.-fileName document) "' in get-enclosing-form-fn-name: ") e)
      nil)))

(defn provideCompletionItems
  "Provides basic hardcoded autocomplete suggestions."
  [document position _token _context]
  ; (.appendLine (joyride/output-channel)  "1")
  (when (utils/is-cljd-file? document) 
    (when-let [w-name (get-enclosing-form-fn-name document position)]
      (let [{:keys [name constructor]}           (utils/parse-widget-name w-name) 
            {:keys [constructors_json]}          (get dart-docs/widgets-data name) 
            {:keys [positional_args named_args]} (->> constructors_json
                                                      (filter #(= constructor (:name %)))
                                                      first) 
            suggestions                          (->> (concat positional_args named_args)
                                                      (map :name)
                                                      (remove nil?)
                                                      (map #(str "." %))
                                                      (map #(vscode/CompletionItem. %))
                                                      vec)]

        ;; Set the kind if desired (optional, affects icon)
        (doseq [suggestion suggestions]
          (set! (.-kind suggestion) vscode/CompletionItemKind.Field)) 
        
        (clj->js suggestions)))))

(defn register-cljd-widget-suggestions! []
  (vscode/languages.registerCompletionItemProvider
   "clojure"
   #js{:provideCompletionItems provideCompletionItems}
   "."))