(ns cljd-widget-hover
  (:require ["vscode" :as vscode]
            [get-docs :as get-docs]
            [clojure.string :as string]))

(def widgets-data 
  (->> "/tmp/cljd_flutter_widget_docs.json"
   get-docs/read-json-sync 
   (map (fn [[k v]]
          [k 
           (get-docs/format-widget-docs->markdown (name k) v)]))
   (into {})))




(defn- provide-cljd-widget-hover [document position _token] 
  (when (.endsWith (.-fileName document) ".cljd") 
   (let [word-range (-> document (.getWordRangeAtPosition position))
         ;; (.getWordRangeAtPosition position #js #/[-_a-zA-Z0-9\/\.]+/) 
         ]
     (when word-range 
       (let [word            (.getText document word-range) 
             parts           (clojure.string/split word #"/")
             flutter-widget? (when (= (count parts) 2)
                               (let [[ns-symbol symbol] parts]
                                 (and (= "m" ns-symbol)
                                      (= (first symbol)
                                         (.toUpperCase (first symbol))))))]
         (when flutter-widget? 
           (let [markdown-string         
                 (vscode/MarkdownString.
                  (get widgets-data (-> parts second keyword))
                  )]
             (new vscode/Hover markdown-string word-range))))))))


(defn register-cljd-widget-provider! [] 
  (vscode/languages.registerHoverProvider
   "clojure" ;; Target clojure language ID
   #js {:provideHover provide-cljd-widget-hover}))

;; Call this function when your extension activates
;; (register-cljd-widget-provider!)

(comment
  (register-cljd-widget-provider!))
