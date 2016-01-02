(ns sodium.s-widgets
  (:require [sodium.core :refer :all])
  (:require [clojure.string :as s])
  (:import [nz.sodium Cell  CellLoop Listener Stream StreamSink Operational Transaction Unit])
  (:import [javax.swing JButton JFrame JLabel JTextField SwingUtilities])
  (:import [java.awt FlowLayout])
  (:import [java.awt.event ActionListener])
  (:import [javax.swing.event DocumentEvent DocumentListener]))

(defn update-text [source sink]
  (let [text (.getText source)]
    (SwingUtilities/invokeLater (fn []
                                  (if (not= text nil)
                                    (do
                                      (.send sink text)))))))
                                          
(defn listen [source sink]
  (let [dl (proxy [DocumentListener] []
             (insertUpdate[e] (update-text source sink))
             (removeUpdate [e] (update-text source sink))
             (changedUpdate [e] (update-text source sink)))]
    (.. source getDocument
        (addDocumentListener dl))
    dl))

(defn s-button
  ([label] (s-button label (Cell. true)))
  ([label enabled]
     (let [s-clicked-sink (StreamSink.)
           l (atom 0)
           button (proxy [JButton] [label]
                    (removeNotify []
                      (.unlisten @l)
                      (proxy-super removeNotify)))]
       (.addActionListener button
                           (proxy [ActionListener] []
                             (actionPerformed [event] (.send s-clicked-sink Unit/UNIT))))
       (Transaction/post (fn []
                           (.setEnabled button (.sample enabled))))
       (reset! l (.listen (Operational/updates enabled) (handler [ena]
                                                                 (.println *err* "in s-button handler")
                                                                 (if (SwingUtilities/isEventDispatchThread)
                                                                   (.setEnabled button ena)
                                                                   (SwingUtilities/invokeLater (fn []
                                                                                                 (.setEnabled button ena)))))))
       {:jbutton button :s-clicked s-clicked-sink :listner l})))
     
         

(defn s-label
  [c-text]
  (let [l (atom false)
        label (proxy [JLabel] [""]
                (removeNotify []
                  (.unlisten @l)
                  (proxy-super removeNofify)))]
    (reset! l (.listen (Operational/updates c-text)
                       (handler [t] (if (SwingUtilities/isEventDispatchThread)
                                      (.setText label t)
                                      (SwingUtilities/invokeLater (fn [t] (.setText label ) t))))))
    (Transaction/post (fn [] (SwingUtilities/invokeLater (fn []
                                                         (.setText label (.sample c-text))))))
    label))

(defn s-text-field
  ([init-text] (s-text-field (Stream.) init-text 15))
  ;([^String init-text ^Long width] (s-text-field (Stream.) init-text width))
  ([^Stream s-text ^String init-text] (s-text-field s-text init-text 15))
  ([^Stream s-text ^String init-text ^long width] (s-text-field s-text init-text width (Cell. true)))
  ([^Stream s-text ^String init-text ^long width ^Cell enabled]
   (let [s-decrement (StreamSink.)
         allow (.map
                (.accum
                 (.orElse
                  (.map s-text (apply1 [u] 1))
                  s-decrement)
                 0
                 (apply2 [d b] (+ b d)))
                (apply1 [b] (== b 0)))
         l (atom 0)
         s-user-changes (StreamSink.)
         text (.hold (.orElse (.gate s-user-changes allow) s-text) init-text)
         s-text-field (proxy [JTextField] [init-text width]
                        (removeNotify []
                          (.unlisten @l)
                          (proxy-super removeNotify)))
         dl (listen s-text-field s-user-changes)]
     (Transaction/post (fn [] (.setEnabled s-text-field (.sample enabled))))
     (reset! l (.append (.listen s-text (handler [text] (SwingUtilities/invokeLater
                                                         (fn []
                                                           (.. s-text-field getDocument
                                                               (removeDocumentListener dl))
                                                           (.setText s-text-field text)
                                                           (.. s-text-field getDocument
                                                               (addDocumentListener dl))
                                                           (.send s-decrement -1)))))
                        (.listen (Operational/updates enabled)
                                 (handler [ena] (if (SwingUtilities/isEventDispatchThread)
                                                  (do
                                                    (println "dispatch thread")
                                                    (.setEnabled s-text-field ena))
                                                  (do
                                                    (println "dispatch else")
                                                    (SwingUtilities/invokeLater (fn []
                                                                                (.setEnabled s-text-field ena)))))))))
     {:jtext s-text-field :cell text :stream s-user-changes :dl dl})))
  
(defn label
  []
 (let [frame (JFrame. "label")
       msg (s-text-field "Hello")
       label (s-label (:cell msg))]
   (doto frame
     (.setLayout (FlowLayout.))
                                        ;(.setDefaultCloseOperation JFrame/EXIT_ON_CLOSE)
     (.add (:jtext msg))
     (.add label)
     (.setSize 400 160)
     (.setVisible true))))

(defn frp-reverse
  []
 (let [frame (JFrame. "reverse")
       msg (s-text-field "Hello")
       reversed (.map (:cell msg) (apply1 [t]
                                          (s/reverse t)))
       label (s-label reversed)]
   (doto frame
     (.setLayout (FlowLayout.))
                                        ;(.setDefaultCloseOperation JFrame/EXIT_ON_CLOSE)
     (.add (:jtext msg))
     (.add label)
     (.setSize 400 160)
     (.setVisible true))))

(defn gamechat
  []
  (let [frame (JFrame. "gamechat")
        onegai (s-button "Onegai shimasu" (Cell. true))
        thanks (s-button "Thank you" (Cell. true))
        s-onegai (.map (:s-clicked onegai) (apply1 [u](str "Onegai shimasu")))
        s-thanks (.map (:s-clicked thanks) (apply1 [u] (str "Thank you")))
        s-canned (.orElse s-onegai s-thanks)
        text (s-text-field s-canned "")]
    (doto frame
      (.setLayout (FlowLayout.))
                                        ;(.setDefaultCloseOperation JFrame/EXIT_ON_CLOSE)
      (.add (:jtext text))
      (.add (:jbutton onegai))
      (.add (:jbutton thanks))
      (.setSize 400 160)
      (.setVisible true))))

(defn redgreen
  []
  (let [frame (JFrame. "redgreen")
        red (s-button "red")
        green (s-button "green")
        s-red (.map (:s-clicked red) (apply1 [u] (str "red")))
        s-green (.map (:s-clicked green) (apply1 [u] (str "green")))
        s-color (.orElse s-red s-green)
        color (.hold s-color "")
        lbl (s-label color)]
    (doto frame
      (.setLayout (FlowLayout.))
                                        ;(.setDefaultCloseOperation
                   ;JFrame/EXIT_ON_CLOSE)
      (.add (:jbutton red))
      (.add (:jbutton green))
      (.add lbl)
      (.setSize 400 160)
      (.setVisible true))))

(defn translate
  []
  (let [frame (JFrame. "translate")
        english (s-text-field "I like FRP")
        translate (s-button "Translate")
        s-latin (.snapshot (:s-clicked translate) (:cell english) (apply2 [u txt]
                                                                          (.trim (.. txt trim
                                                                                     (replaceAll " |$" "us ")))))
        latin (.hold s-latin "")
        lbl-latin (s-label latin)]
    (doto frame
      (.setLayout (FlowLayout.))
                                        ;(.setDefaultCloseOperation
                                        ;JFrame/EXIT_ON_CLOSE)
      (.add (:jtext english))
      (.add (:jbutton translate))
      (.add lbl-latin)
      (.setSize 400 160)
      (.setVisible true))))

(defn spinner
  []
  (let [view (JFrame. "spinner")]
    (Transaction/runVoid (fn []
                           (let [value (CellLoop.)
                               lbl-value (s-label (.map value (apply1 [i] (str i))))
                               plus (s-button "+")
                               minus (s-button "-")
                                 s-plus-delta (.map (:s-clicked plus) (apply1 [u] (println "plus")
                                                                              1))
                               s-minus-delta (.map (:s-clicked minus) (apply1 [u] -1))
                               s-delta (.orElse s-plus-delta s-minus-delta)
                               s-update (.snapshot s-delta value (apply2 [delta value_] (+ delta value_)))]
                             (.loop value (.hold s-update 0))
                             (doto view
                               (.setLayout (FlowLayout.))
                                        ;(.setDefaultCloseOperation
                                        ;JFrame/EXIT_ON_CLOSE)
                               (.add lbl-value)
                               (.add (:jbutton plus))
                               (.add (:jbutton minus))))))
  (doto view
    (.setSize 400 160)
    (.setVisible true))))

(defn add
  []
  (let [frame (JFrame. "add")
        txt-a (s-text-field "5")
        txt-b (s-text-field "10")
        parse-int (fn [t] (try
                           (Integer/parseInt t)
                           (catch NumberFormatException e
                             0)))
        a (.map (:cell txt-a) (apply1 [t] (parse-int t)))
        b (.map (:cell txt-b) (apply1 [t] (parse-int t)))
        sum (Cell/lift (apply2 [a_ b_] (println (str a_ " + " b_))
                                                (+ a_ b_)) a b)
        lbl-sum (s-label (.map sum (apply1 [i] (str i))))]
    (doto frame
      (.setLayout (FlowLayout.))
     ;(.setDefaultCloseOperation JFrame/EXIT_ON_CLOSE)
      (.add (:jtext txt-a))
      (.add (:jtext txt-b))
      (.add lbl-sum)
      (.setSize 400 160)
      (.setVisible true))))
      

(defn -main
  [& args]
  (add)
  (spinner)
  (translate)
  (redgreen)
  (gamechat)
  (frp-reverse)
  (label))