(ns cljd-widget-hover
  (:require ["vscode" :as vscode]
            [get-docs :as get-docs] 
            [joyride.core :as joyride]
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
            (let [s               (-> parts
                                      second
                                      (clojure.string/split #"\.") ; widget constructor could be m/WidgetName.something
                                      first
                                      keyword
                                      widgets-data
                                      :doc) 
                  markdown-string (vscode/MarkdownString. s)]
              (new vscode/Hover markdown-string word-range))))))))


(defn register-cljd-widget-provider! [] 
  (vscode/languages.registerHoverProvider
   "clojure" ;; Target clojure language ID
   #js {:provideHover provide-cljd-widget-hover}))
