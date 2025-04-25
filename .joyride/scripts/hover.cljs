(ns hover
  (:require ["vscode" :as vscode]
            [dart-docs] 
            [utils]
            [clojure.string :as str]))

(defn- provide-cljd-widget-hover [document position _token] 
  (when (utils/is-cljd-file? document) 
    ;; (.getWordRangeAtPosition position #js #/[-_a-zA-Z0-9\/\.]+/) 
    (let [word-range (-> document (.getWordRangeAtPosition position))  ]
      (when word-range 
        (let [word            (.getText document word-range) 
              parts           (str/split word #"/")
              flutter-widget? (when (= (count parts) 2)
                                (let [[ns-symbol symbol] parts]
                                  (and (= "m" ns-symbol)
                                       (= (first symbol)
                                          (.toUpperCase (first symbol))))))] 
          
          (when flutter-widget? 
            (let [{:keys [name]}  (utils/parse-widget-name word)
                  doc             (-> (get dart-docs/widgets-data name)
                                      :doc) 
                  markdown-string (vscode/MarkdownString. doc)]
              (new vscode/Hover markdown-string word-range))))))))


(defn register-cljd-widget-provider! [] 
  (vscode/languages.registerHoverProvider
   "clojure" ;; Target clojure language ID
   #js {:provideHover provide-cljd-widget-hover}))
