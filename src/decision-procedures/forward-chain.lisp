;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -*- Mode: Lisp -*- ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; arrays.lisp -- 
;; Author          : David Cyrluk
;; Created On      : 1998/12/01 19:08:45
;;
;; HISTORY
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(in-package dp)

(defvar *use-fc-hash* nil)

(defdpstruct (forward-chains)
  (orig-rules nil :type list)
  (partial-rules nil :type list)
  (pred-use (dp-make-eq-hash-table) :type hash-table)
  (term-use (dp-make-eq-hash-table) :type hash-table))


(defvar *initial-forward-chains* (make-forward-chains))

(defun initial-forward-chains ()
  (make-forward-chains))

(defun clr-forward-chains (fcs)
  (setf (forward-chains-orig-rules fcs) nil)
  (setf (forward-chains-partial-rules fcs) nil)
  (clrhash (forward-chains-pred-use fcs))
  (clrhash (forward-chains-term-use fcs))
  fcs)

(defun copy-forward-chains-and-hash (new-forward-chains old-forward-chains)
  (setf (forward-chains-orig-rules new-forward-chains)
	(forward-chains-orig-rules old-forward-chains))
  (setf (forward-chains-partial-rules new-forward-chains)
	(forward-chains-partial-rules old-forward-chains))
  ;(copy-hash-table (forward-chains-hash new-forward-chains)
;		   (forward-chains-hash old-forward-chains))
  new-forward-chains)

(defdpstruct (forward-chain)
  (pos-antecedents nil :type list)
  (neg-antecedents nil :type list)
  (consequent nil :type node)
  (name "" :type string))

(defstruct (new-fc-info (:type vector))
  (subst nil :type list)
  (antecedents nil :type list))

(defun fc-match (lhs antecedents &optional rhs)
  (loop with subst
	with succ
	for ant in antecedents
	do (multiple-value-setq (subst succ)
	       (match lhs ant))
	;;; ant is the pattern, lhs the term
	when succ collect
	(make-new-fc-info :subst subst
			  :antecedents
			  (if rhs
			      (subst rhs ant antecedents :test #'eq)
			      (remove ant antecedents :test #'eq)))))

(defun make-new-fc (name subst pos-antec neg-antec conseq)
  (let ((new-pos (loop for a in pos-antec
		       collect (apply-subst a subst)))
	(new-neg (loop for a in neg-antec
		       collect (apply-subst a subst)))
	(new-conseq (apply-subst conseq subst)))
    (make-forward-chain :pos-antecedents new-pos
			:neg-antecedents new-neg
			:consequent new-conseq
			:name name)))

(defvar *trace-forward-chain* t)

(defun forward-chain (eqn cong-state)
  (let* ((fcs (forward-chains cong-state))
	 (lhs (lhs eqn))
	 (rhs (rhs eqn))
	 (poss-fcs (get-applicable-fcs lhs fcs)))
    (let ((new-fcs (loop for fc in poss-fcs
			 nconc (forward-chain-1 lhs rhs fc))))
      (process-new-fcs new-fcs fcs cong-state)
      cong-state)))

(defun process-new-fcs (new-fcs old-fcs cong-state)
  (let ((new-consequents nil))
    (loop for new-fc in new-fcs
	  if (and (null (forward-chain-pos-antecedents new-fc))
		  (null (forward-chain-neg-antecedents new-fc)))
	  do (when *trace-forward-chain*
	       (format t "~% ~A forward-chains to ~A"
		 (forward-chain-name new-fc)
		 (forward-chain-consequent new-fc)))
	  (setq new-consequents (cons (forward-chain-consequent new-fc)
				      new-consequents))
	  else do (setf (forward-chains-partial-rules old-fcs)
			(cons new-fc (forward-chains-partial-rules old-fcs))))
    (loop for conseq in new-consequents
	  do
	  (process* (canon conseq cong-state 'no-mod)
		    cong-state))))

(defun get-applicable-fcs (term fcs)
  (if *use-fc-hash*
      (let ((pred (if (application-p term)
		   (funsym term)
		   term)))
	(gethash pred (forward-chains-pred-use fcs)))
      (forward-chains-partial-rules fcs)))

(defun forward-chain-1 (lhs rhs fc)
  (cond
   ((true-p rhs)
    (forward-chain-pos lhs fc))
   ((false-p rhs)
    (forward-chain-neg lhs fc))
   (t (forward-chain-both lhs rhs fc))))

(defun forward-chain-pos (lhs fc)
  (let* ((pos-antecedents (forward-chain-pos-antecedents fc))
	 (neg-antecedents (forward-chain-neg-antecedents fc))
	 (new-fc-infos (fc-match lhs pos-antecedents)))
    (loop for fci in new-fc-infos
	  collect (make-new-fc (forward-chain-name fc)
			       (new-fc-info-subst fci)
			       (new-fc-info-antecedents fci)
			       neg-antecedents
			       (forward-chain-consequent fc)))))

(defun forward-chain-neg (lhs fc)
  (let* ((pos-antecedents (forward-chain-pos-antecedents fc))
	 (neg-antecedents (forward-chain-neg-antecedents fc))
	 (new-fc-infos (fc-match lhs neg-antecedents)))
    (loop for fci in new-fc-infos
	  collect (make-new-fc (forward-chain-name fc)
			       (new-fc-info-subst fci)
			       pos-antecedents
			       (new-fc-info-antecedents fci)
			       (forward-chain-consequent fc)))))

(defun forward-chain-both (lhs rhs fc)
  (let* ((pos-antecedents (forward-chain-pos-antecedents fc))
	 (neg-antecedents (forward-chain-neg-antecedents fc))
	 (pos-fc-infos (fc-match lhs pos-antecedents rhs))
	 (neg-fc-infos (fc-match lhs neg-antecedents rhs)))
    (let ((pos-fcs
	   (loop for fci in pos-fc-infos
		 collect (make-new-fc (forward-chain-name fc)
				      (new-fc-info-subst fci)
				      (new-fc-info-antecedents fci)
				      neg-antecedents
				      (forward-chain-consequent fc))))
	  (neg-fcs
	   (loop for fci in neg-fc-infos
		 collect (make-new-fc (forward-chain-name fc)
				      (new-fc-info-subst fci)
				      pos-antecedents
				      (new-fc-info-antecedents fci)
				      (forward-chain-consequent fc)))))
      (append pos-fcs neg-fcs))))

