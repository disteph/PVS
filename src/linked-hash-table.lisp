(in-package :pvs)

(defstruct (linked-hash-table (:conc-name lhash-))
  table
  next)

(defun make-lhash-table (&key (test 'eql) (size 67)
				 (rehash-size 1.2) (rehash-threshold 0.6407767)
				 (hash-function nil) (values t)
				 (weak-keys nil))
  (make-linked-hash-table
   :table (make-hash-table :test test :size size :rehash-size rehash-size
			   :rehash-threshold rehash-threshold
			   :hash-function hash-function :values values
			   :weak-keys weak-keys)))

(defun copy-lhash-table (lht &key (size 67) (rehash-size 1.2)
			     (rehash-threshold 0.6407767))
  (let ((ht (if (linked-hash-table-p lht)
		(lhash-table lht)
		lht)))
    (when (and (lhash-next lht)
	       (lhash-next (lhash-next lht)))
      (break "Two levels already?"))
    (assert (hash-table-p ht))
    (make-linked-hash-table
     :table (make-hash-table
	     :test (hash-table-test ht)
	     :size size
	     :rehash-size rehash-size
	     :rehash-threshold rehash-threshold
	     :hash-function (excl:hash-table-hash-function ht)
	     :values (excl:hash-table-values ht)
	     :weak-keys (excl:hash-table-weak-keys ht))
     :next (if (linked-hash-table-p lht)
	       lht
	       (make-linked-hash-table
		:table ht)))))

(defun get-lhash (key lhashtable &optional default)
  (if (hash-table-p (lhash-table lhashtable))
      (multiple-value-bind (value there?)
	  (gethash key (lhash-table lhashtable))
	(if there?
	    (values value there?)
	    (if (lhash-next lhashtable)
		(get-lhash key (lhash-next lhashtable) default)
		(values default nil))))
      (if (lhash-next lhashtable)
	  (get-lhash key (lhash-next lhashtable) default)
	  (values default nil))))

(defsetf get-lhash (key lhashtable &optional default) (value)
  `(setf-get-lhash ,key ,lhashtable ,default ,value))

(defun setf-get-lhash (key lhashtable default value)
  (if (hash-table-p (lhash-table lhashtable))
      (setf (gethash key (lhash-table lhashtable) default) value)
      (let ((ht (funcall (lhash-table lhashtable))))
	(setf (lhash-table lhashtable) ht)
	(setf (gethash key ht default) value))))

;;; Similar to maphash, but makes sure not to revisit keys duplicated
;;; at lower levels.
(defvar *map-lhash-keys-visited*)

(defun map-lhash (function lhash)
  (let ((*map-lhash-keys-visited* nil))
    (map-lhash* function lhash)))

(defun map-lhash* (function lhash)
  (let ((ht (lhash-table lhash)))
    (if (hash-table-p ht)
	(maphash #'(lambda (x y)
		     (unless (member x *map-lhash-keys-visited*
				     :test (hash-table-test ht))
		       (when (lhash-next lhash)
			 (push x *map-lhash-keys-visited*))
		       (funcall function x y)))
		 (lhash-table lhash))
	(when (lhash-next lhash)
	  (map-lhash* function (lhash-next lhash))))))