(var seq nil)                    ; forward declaration of seq function

(fn first [s]
  "Return first element of a sequence."
  (match (seq s)
    s* (s* true)
    _ nil))

(local empty-cons
  (let [e []]
    (setmetatable e {:__len #0
                     :__fennelview #"@seq()"
                     :__lazy-seq/type :empty-cons
                     :__newindex #nil
                     :__name "cons"
                     :__pairs #(values next [] nil)
                     :__call #(if $2 nil e)})))

(fn rest [s]
  "Return the tail of a sequence.

If the sequence is empty, returns empty sequence."
  (match (seq s)
    s* (s* false)
    _ empty-cons))

(fn gettype [x]
  (match (?. (getmetatable x) :__lazy-seq/type)
    t t
    _ (type x)))

(fn realize [c]
  ;; force realize single cons cell
  (doto c (c)))

(fn next* [s]
  "Return the tail of a sequence.

If the sequence is empty, returns nil."
  (seq (realize (rest s))))

;;; Cons cell

(fn view-seq [list options view indent elements]
  (table.insert elements (view (first list) options indent))
  (let [tail (next* list)]
    (when (= :cons (gettype tail))
      (view-seq tail options view indent elements)))
  elements)

(fn pp-seq [list view options indent]
  (let [items (view-seq list options view (+ indent 5) [])
        lines (icollect [i line (ipairs items)]
                (if (= i 1) line (.. "     " line)))]
    (doto lines
      (tset 1 (.. "@seq(" (or (. lines 1) "")))
      (tset (length lines) (.. (. lines (length lines)) ")")))))

(local allowed-types
  {:cons true
   :empty-cons true
   :lazy-cons true
   :nil true
   :table true})

(fn cons [...]
  "Construct a cons cell.
Second element must be either a table or a sequence, or nil."
  (assert (= 2 (select "#" ...)) "expected two arguments for cons")
  (let [(h t) ...]
    (assert (. allowed-types (gettype t))
            "expected nil, cons or table as a tail")
    (setmetatable [] {:__call #(if $2 h (match (seq t) s s nil empty-cons))
                      :__lazy-seq/type :cons
                      :__len #(do (var (s len) (values $ 0))
                                  (while s
                                    (set (s len) (values (next* s) (+ len 1))))
                                  len)
                      :__pairs #(values (fn [_ s]
                                          (if (not= empty-cons s)
                                              (let [tail (next* s)]
                                                (match (gettype tail)
                                                  :cons (values tail (first s))
                                                  _ (values empty-cons (first s))))
                                              nil))
                                        nil $)
                      :__name "cons"
                      :__fennelview pp-seq})))

(set seq
     (fn [t size]
       "Construct a sequence out of a table or another sequence `t`.
Takes optional `size` argument for defining the length of the
resulting sequence.  Since sequences can contain `nil` values,
transforming packed table to a sequence is possible by passing the
value of `n` key from such table.  Returns `nil` if given empty table,
or empty sequence."
       (match (gettype t)
         :cons t
         :lazy-cons (seq (realize t))
         :empty-cons nil
         :nil nil
         ;; TODO: think thru how to support associative data
         ;;       structures and user-defined table-based data
         ;;       structures
         :table (do (var res nil)
                    (for [i (or size (length t)) 1 -1]
                      (set res (cons (. t i) res)))
                    res)
         _ (error (: "expected table or sequence, got %s" :format _) 2))))

(fn lazy-seq [f]
  "Create lazy sequence from the result of function `f`.
Delays execution of `f` until sequence is consumed.

See `lazy-seq` macro from init-macros.fnl for more convenient usage."
  (let [lazy-cons (cons nil nil)
        realize (fn []
                  (let [s (seq (f))]
                    (if (not= nil s)
                        (setmetatable lazy-cons (getmetatable s))
                        (setmetatable lazy-cons (getmetatable empty-cons)))))]
    (setmetatable lazy-cons {:__call #((realize) $2)
                             :__fennelview #((. (getmetatable (realize)) :__fennelview) $...)
                             :__len #(length (realize))
                             :__pairs #(pairs (realize))
                             :__name "lazy cons"
                             :__lazy-seq/type :lazy-cons})))

(fn every? [pred coll]
  "Check if `pred` is true for every element of a sequence `coll`."
  (match (seq coll)
    s (if (pred (first s))
          (match (next* s)
            r (every? pred r)
            _ true)
          false)
    _ false))

(fn some? [pred coll]
  "Check if `pred` returns logical true for any element of a sequence
`coll`."
  (match (seq coll)
    s (or (pred (first s))
          (match (next* s)
            r (some? pred r)
            _ nil))
    _ nil))

(fn seq-pack [s]
  "Pack sequence into sequential table with size indication."
  (let [res []]
    (var n 0)
    (each [_ v (pairs (seq s))]
      (set n (+ n 1))
      (tset res n v))
    (doto res (tset :n n))))

(local unpack (or table.unpack _G.unpack))
(fn seq-unpack [s]
  "Unpack sequence items to multiple values."
  (let [t (seq-pack s)]
    (unpack t 1 t.n)))

(fn concat [...]
  "Return a lazy sequence of concatenated sequences."
  (match (select "#" ...)
    0 nil
    1 (seq ...)
    2 (let [(x y) ...]
        (match (seq x)
          s (lazy-seq #(cons (first s) (concat (rest s) y)))
          nil y))
    _ (concat (concat (pick-values 2 ...)) (select 3 ...))))

(fn map [f ...]
  "Map function `f` over every element of a collection `col`.
Returns lazy sequence.

# Examples

```fennel
(map #(+ $ 1) [1 2 3]) ;; => @seq(2 3 4)
(local res (map #(+ $ 1) [:a :b :c])) ;; will blow up when realized
```"
  (match (select "#" ...)
    0 nil
    1 (let [(col) ...]
        (lazy-seq #(match (seq col)
                     x (cons (f (first x)) (map f (seq (rest x))))
                     _ nil)))
    2 (let [(s1 s2) ...]
        (lazy-seq #(let [s1 (seq s1) s2 (seq s2)]
                     (if (and s1 s2)
                         (cons (f (first s1) (first s2)) (map f (rest s1) (rest s2)))
                         nil))))
    3 (let [(s1 s2 s3) ...]
        (lazy-seq #(let [s1 (seq s1) s2 (seq s2) s3 (seq s3)]
                     (if (and s1 s2 s3)
                         (cons (f (first s1) (first s2) (first s3))
                               (map f (rest s1) (rest s2) (rest s3)))
                         nil))))
    _ (let [s (seq [...] (select "#" ...))]
        (lazy-seq #(if (every? #(not= nil (seq $)) s)
                       (cons (f (seq-unpack (map first s)))
                             (map f (seq-unpack (map rest s))))
                       nil)))))

(fn take [n coll]
  "Take `n` elements from the collection `coll`.
Returns a lazy sequence of specified amount of elements.

# Examples

Take 10 element from a sequential table

```fennel
(take 10 [1 2 3]) ;=> @seq(1 2 3)
(take 5 [1 2 3 4 5 6 7 8 9 10]) ;=> @seq(1 2 3 4 5)
```"
  (lazy-seq #(if (> n 0)
                 (match (seq coll)
                   s (cons (first s) (take (- n 1) (rest s))))
                 nil)))

(fn drop [n coll]
  "Drop `n` elements from collection, returning a lazy sequence of
remaining elements."
  (let [step (fn step [n coll]
               (let [s (seq coll)]
                 (if (and (> n 0) s)
                     (step (- n 1) (rest s))
                     s)))]
    (lazy-seq #(step n coll))))

(fn filter [pred coll]
  "Returns a lazy sequence of the items in the `coll` for which `pred`
returns logical true."
  (lazy-seq
   #(match (seq coll)
      s (let [x (first s) r (rest s)]
          (if (pred x)
              (cons x (filter pred r))
              (filter pred r)))
      _ nil)))

(fn keep [f coll]
  "Returns a lazy sequence of the non-nil results of calling `f` on the
items of the `coll`."
  (lazy-seq #(match (seq coll)
               s (match (f (first s))
                   x (cons x (keep f (rest s)))
                   nil (keep f (rest s)))
               _ nil)))


;;; Range

(fn inf-range [x step]
  ;; infinite lazy range builder
  (lazy-seq #(cons x (inf-range (+ x step) step))))

(fn fix-range [x end step]
  ;; fixed lazy range builder
  (lazy-seq #(if (or (and (>= step 0) (< x end))
                     (and (< step 0) (> x end)))
                 (cons x (fix-range (+ x step) end step))
                 nil)))

(fn range [...]
  "Create a possibly infinite sequence of numbers.

If one argument is specified, returns a finite sequence from 0 up to this argument.
If two arguments were specified, returns a finite sequence from lower to, but not included, upper bound.
A third argument provides step interval.

If no arguments were specified, returns an infinite sequence starting at 0.

# Examples

Various ranges:

```fennel
(range 10) ;; => @seq(0 1 2 3 4 5 6 7 8 9)
(range 4 8) ;; => @seq(4 5 6 7)
(range 0 -5 -2) ;; => @seq(0 -2 -4)
(take 10 (range)) ;; => @seq(0 1 2 3 4 5 6 7 8 9)
```"
  (match (select "#" ...)
    0 (inf-range 0 1)
    1 (let [(end) ...]
        (fix-range 0 end 1))
    2 (let [(x end) ...]
        (fix-range x end 1))
    _ (fix-range ...)))

;;; Utils

(fn realized? [s]
  "Check if sequence is fully realized.

Use at your own risk on infinite sequences."
  (var (s not-done) (values s true))
  (while (and not-done s)
    (if (= :lazy-cons (gettype s))
        (set not-done false)
        (set s (seq (rest s)))))
  not-done)

(fn dorun [s]
  "Realize whole sequence for side effects.

Walks whole sequence, realizing each cell.  Use at your own risk on
infinite sequences."
  (match (seq s)
    s* (dorun (next* s*))
    _ nil))

(fn doall [s]
  "Realize whole lazy sequence.

Walks whole sequence, realizing each cell.  Use at your own risk on
infinite sequences."
  (doto s (dorun)))

(setmetatable
 {: take
  : range
  : concat
  : map
  : filter
  : keep
  : seq
  :lazy-seq* lazy-seq
  : doall
  : dorun
  : realized?
  : every?
  : some?
  : seq-pack
  : seq-unpack
  : cons
  : first
  : rest
  :next next*}
 {:__index {:_DESCRIPTION "Lazy sequence library for Fennel and Lua."
            :_MODULE_NAME "lazy-seq.fnl"}})
