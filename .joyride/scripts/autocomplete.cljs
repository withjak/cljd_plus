(ns autocomplete ;; Choose an appropriate namespace
  (:require ["vscode" :as vscode]
            [rewrite-clj.zip :as z]))

(defn- vscode->rewrite-pos 
  [position]
  ;; VS Code is 0-based, rewrite-clj is 1-based
  {:line (inc (.-line position))
   :char (inc (.-character position))})

(defn- rewrite->vscode-pos 
  [row col] 
  (vscode/Position. (dec row) (dec col)))

(defn- pos-within-node?
  "Checks if the 1-based [line char] is within the node's bounds."
  [node line char]
  (let [m (meta node)]
    (and m
         (:row m) ; Ensure metadata exists
         ;; Check line containment (this part is fine)
         (>= line (:row m))
         (<= line (:end-row m))
         ;; Check character containment, handling single/multi-line nodes
         (if (= (:row m) (:end-row m))
           ;; Single line node check
           (and (>= char (:col m))
                (< char (:end-col m)))
           ;; Multi-line node check: Combine start AND end checks
           (and
            ;; Start check: Either on a later line OR on the first line after/at start column
            (or (> line (:row m))
                (>= char (:col m)))
            ;; End check: Either on an earlier line OR on the last line before end column
            (or (< line (:end-row m))
                (< char (:end-col m)))))))) ;; If last line, check end char (exclusive)

(defn- find-smallest-containing-node
  "Finds the smallest node in the zipper that contains the 1-based [line char]"
  [root-zloc line char]
  (->> (iterate z/next root-zloc)
       (take-while (complement z/end?))
       (filter #(pos-within-node? (z/node %) line char))
       ;; Sort by text length (approximated by coordinate difference) to find smallest
       (sort-by (fn [loc]
                  (let [m (meta (z/node loc))]
                    (- (+ (* (- (:end-row m) (:row m)) 10000) ; Weight rows heavily
                          (:end-col m))
                       (:col m))))
                <) ; Ascending order (smallest first)
       first)) ; Take the smallest node

(defn- find-enclosing-form-node
  "Walks up from the start-loc until a list, map, or vector node is found."
  [start-loc]
  (loop [loc start-loc]
    ;; Keep looping as long as loc is not nil (i.e., we haven't gone past the root)
    (when loc
      (if (or (z/list? loc) (z/vector? loc) (z/map? loc))
        loc ;; Found an enclosing collection form, return it
        ;; Otherwise, move up one level and continue the loop.
        ;; If (z/up loc) is nil, the next iteration's `when` will fail, terminating the loop.
        (recur (z/up loc))))))

(defn get-enclosing-form-range
  "Parses the document text and returns a vscode.Range for the
   innermost form (list, vector, or map) containing the position.
   Returns nil if parsing fails or no enclosing form is found."
  [document position]
  (try
    (let [text        (.getText document)
          rewrite-pos (vscode->rewrite-pos position)]
      (when-let [root-zloc (z/of-string text {:track-position? true})]
        (when-let [containing-node-loc (find-smallest-containing-node root-zloc
                                                                      (:line rewrite-pos)
                                                                      (:char rewrite-pos))]
          (when-let [form-loc (find-enclosing-form-node containing-node-loc)]
            (let [form-node (z/node form-loc) 
                  m         (meta form-node)] 
              (when (and (:row m) (:col m) (:end-row m) (:end-col m)) ;; Check if meta is valid
                (let [start-pos (rewrite->vscode-pos (:row m) (:col m))
                      end-pos   (rewrite->vscode-pos (:end-row m) (:end-col m))]
                  (vscode/Range. start-pos end-pos))))))))
    (catch :default e
      ;; Log error or handle zipper/parsing errors if necessary
      ;; (.error js/console "Error finding enclosing form:" e)
      nil)))

;; --- Example Usage (e.g., in a command or provider) ---
;; (let [editor (.-activeTextEditor vscode/window)
;;       document (.-document editor)
;;       position (-> editor .-selection .-active)]
;;   (when-let [form-range (get-enclosing-form-range document position)]
;;     (.showInformationMessage vscode/window
;;                              (str "Found form range: "
;;                                   (.-line (.-start form-range)) "," (.-character (.-start form-range)) " -> "
;;                                   (.-line (.-end form-range)) "," (.-character (.-end form-range))))
;;     ;; You can now use form-range, e.g., get the text:
;;     ;; (.getText document form-range)
;;     ))

(comment 
  (-> 
   (z/of-string  
    "(m/Column 
      (m/Row
        #_
        (m/Text)))"
    {:track-position? true}))
  
  (z/whitespace-or-comment?
   (z/of-string
    "
     (m/Column 
         (m/Row
           #_
           (m/Text)))"
    {:track-position? true}))
  )