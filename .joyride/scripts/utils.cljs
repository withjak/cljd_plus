(ns utils
  (:require [clojure.string :as str]))

(defn is-cljd-file? 
  [document]
  (.endsWith (.-fileName document) ".cljd"))

(defn parse-widget-name 
  [w]
  ; adduming the validation has already done
  (let [[ns name-]         (str/split w #"/")
        [name constructor] (str/split name- #"\.")]
    {:name        (keyword name) 
     :constructor (if constructor 
                    (str name "." constructor)
                    name)
     :ns          ns}))