(ns autocomplete ;; Choose an appropriate namespace
  (:require ["vscode" :as vscode]
            [rewrite-clj.zip :as z]
            [joyride.core :as joyride] 
            [clojure.string :as string]
            [cljd-widget-hover :as cwh]))

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
  (when (and (= "clojure" (.-languageId document))
             (.endsWith (.-fileName document) ".cljd"))  
    (.appendLine (joyride/output-channel)  "2")
    (when-let [w-name (get-enclosing-form-fn-name document position)]
      (let [wname (-> w-name
                      (string/split #"/")
                      last) 
            {:keys [_doc constructors_json]}     (-> wname
                                                     (string/split #"\.")
                                                     first
                                                     keyword
                                                     (->> (get cwh/widgets-data))) 
            {:keys [positional_args named_args]} (->> constructors_json
                                                      (filter #(= wname (:name %)))
                                                      first) 
            suggestions  (->> (concat positional_args named_args)
                              (map :name)
                              (remove nil?)
                              (map #(str "." %))
                              (map #(vscode/CompletionItem. %))
                              vec)]

        ;; Set the kind if desired (optional, affects icon)
        (doseq [suggestion suggestions]
         (set! (.-kind suggestion) vscode/CompletionItemKind.Field)) 
        
        
        (clj->js suggestions)))))


(comment 
  (let [code "(m/Widget some .title :hello .children [(m/text :bla) ] )"
        tree (z/of-string code {:track-position? true})]
    (->> (iterate z/up tree)
         (take-while (complement nil?))
         (map z/string)))
  
  )