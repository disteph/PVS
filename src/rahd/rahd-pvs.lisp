(in-package :pvs)

(defvar *pvs-rahd-hash*)
(defvar *rahd-pvs-hash*)
(defvar *rahd-var-counter*)

(defstep rahd (&optional (fnums *))
  (then (grind)
	(rahd-simp fnums))
  "Real Algebra in High Dimensions"
  "~%Applying rahd")

(addrule 'rahd-simp () ((fnums *) rahd-args (simplify-division? t))
  (rahd-fun fnums rahd-args simplify-division?)
  "Real Algebra in High Dimensions"
  "~%Applying rahd-simp,")

(defun rahd-fun (fnums rahd-args simplify-division?)
  #'(lambda (ps) (run-rahd ps fnums rahd-args simplify-division?)))

(defun run-rahd (ps fnums rahd-args simplify-division?)
  (let* ((sforms (s-forms (current-goal ps)))
	 (selected-sforms (gather-seq sforms fnums nil #'polynomial-formula?))
	 (remaining-sforms (delete-seq sforms fnums))
	 (*pvs-rahd-hash* (make-pvs-hash-table))
	 (*rahd-pvs-hash* (make-hash-table)))
    (newcounter *rahd-var-counter*)
    (if (null selected-sforms)
	(values 'X nil nil)
	(let* ((rahd-form (translate-to-rahd selected-sforms simplify-division?))
	       (rahd-result (go-rahd rahd-form rahd-args)))
	  (add-rahd-subgoals
	   rahd-result sforms selected-sforms remaining-sforms ps)))))

(defun go-rahd (conj rahd-args)
  (rahd:rahd-reset-state)
  (rahd:g conj)
  (apply #'rahd:go! rahd-args)
  (rahd:extract-non-refuted-cases))

(defun add-rahd-subgoals (rahd-result sforms selected-sforms remaining-sforms ps)
  (if (null rahd-result)
      (values '! nil nil)
      (let ((subgoals
	     (mapcar #'(lambda (c)
			 (create-rahd-subgoal
			  c ps sforms selected-sforms remaining-sforms))
	       (remove-if #'(lambda (sg) (equal sg '((t)))) rahd-result))))
	(if (and (singleton? subgoals)
		 (subsetp (s-forms (car subgoals)) sforms)
		 (subsetp sforms (s-forms (car subgoals))))
	    (values 'X nil nil)
	    (values '? subgoals)))))

(defun create-rahd-subgoal (c ps sforms selected-sforms remaining-sforms)
  (copy (current-goal ps)
    's-forms (nconc
	      (mapcar #'(lambda (fmla)
			  (let* ((pvsfmla (translate-from-rahd fmla))
				 (mem (member pvsfmla sforms
					      :key #'formula :test #'tc-eq)))
			    (assert (null (freevars pvsfmla)))
			    (if mem
				(car mem)
				(make-instance 's-formula 'formula pvsfmla))))
		(car c))
	      remaining-sforms)))

(defun translate-from-rahd (fmla)
  (negate (translate-from-rahd* fmla)))

(defun translate-from-rahd* (fmla)
  (if (listp fmla)
      (case (car fmla)
	(= (make!-equation (translate-from-rahd* (cadr fmla))
			   (translate-from-rahd* (caddr fmla))))
	(< (make!-less (translate-from-rahd* (cadr fmla))
		       (translate-from-rahd* (caddr fmla))))
	(<= (make!-lesseq (translate-from-rahd* (cadr fmla))
			  (translate-from-rahd* (caddr fmla))))
	(> (make!-greater (translate-from-rahd* (cadr fmla))
			  (translate-from-rahd* (caddr fmla))))
	(>= (make!-greatereq (translate-from-rahd* (cadr fmla))
			     (translate-from-rahd* (caddr fmla))))
	(+ (make!-plus (translate-from-rahd* (cadr fmla))
		       (translate-from-rahd* (caddr fmla))))
	(* (make!-times (translate-from-rahd* (cadr fmla))
			(translate-from-rahd* (caddr fmla))))
	(- (if (= (length fmla) 2)
	       (make!-minus (translate-from-rahd* (cadr fmla)))
	       (make!-difference (translate-from-rahd* (cadr fmla))
				 (translate-from-rahd* (caddr fmla)))))
	(t (break "Problem in translation from rahd")))
      (if (numberp fmla)
	  (if (< fmla 0)
	      (make!-minus (make!-number-expr (- fmla)))
	      (make!-number-expr fmla))
	  (let ((ex (gethash fmla *rahd-pvs-hash*)))
	    (assert ex)
	    ex))))     
      

(defun polynomial-formula? (sform)
  (polynomial-formula?* (formula sform)))

(defun polynomial-formula?* (ex)
  ;; Must be equality or inequality over reals
  (or (and (or (equation? ex) (disequation? ex))
	   (every #'(lambda (arg)
		      (some #'(lambda (ty) (subtype-of? ty *real*))
			    (judgement-types+ arg)))
		  (exprs (argument ex))))
      (inequation? ex)
      (and (negation? ex) (polynomial-formula?* (argument ex)))))

(defvar *rahd-typepreds*)

(defun translate-to-rahd (sforms simplify-division?)
  (let* ((*rahd-typepreds* nil)
	 (rahd-fmla (if simplify-division?
			(poly-remove-divisions
			 (mapcar #'formula sforms))
			(mapcar #'(lambda (sform)
				    (list (translate-to-rahd*
					   (negate (formula sform)))))
			  sforms))))
    (append *rahd-typepreds* rahd-fmla)))

(defun poly-remove-divisions (fmlas)
  (mapcar #'(lambda (fms)
	      (mapcar #'translate-to-rahd* fms))
    (mapcan #'poly-remove-division fmlas)))

(defun poly-remove-division (fmla)
  ;; remove divisions in =, /=, <, <=, >, >= formulas between polynomials
  ;; Returns a list of list of formulas (dnf)
  ;; E.g., for (a / b) < (c / d) returns
  ;;           (((b * d > 0) (a * d < b * c)) ((b * d < 0) (a * d > b * c)))
  (assert (compatible? (type fmla) *boolean*))
  (assert (polynomial-formula?* fmla))
  (let* ((nfmla (if (negation? fmla)
		    (args1 fmla)
		    (poly-negate fmla)))
	 (lhs (lift-division (args1 nfmla)))
	 (rhs (lift-division (args2 nfmla))))
    (if (is-division? lhs)
	(let ((n1 (args1 lhs))
	      (d1 (args2 lhs)))
	  (if (is-division? rhs)
	      (let* ((n2 (args1 rhs))
		     (d2 (args2 rhs))
		     (nlhs (make!-times n1 d2))
		     (nrhs (make!-times n2 d1)))
		(case (id (operator nfmla))
		  (= (list (list (make!-equation nlhs nrhs))))
		  (/= (list (list (make!-disequation nlhs nrhs))))
		  (t (let ((cond1 (make!-less (make!-times d1 d2)
					      (make!-number-expr 0)))
			   (cond2 (make!-greatereq (make!-times d1 d2)
						   (make!-number-expr 0))))
		       (case (id (operator nfmla))
			 (<
			  (list (list cond1 (make!-less nlhs nrhs))
				(list cond2 (make!-greatereq nlhs nrhs))))
			 (<=
			  (list (list cond1 (make!-lesseq nlhs nrhs))
				(list cond2 (make!-greater nlhs nrhs))))
			 (>
			  (list (list cond1 (make!-greater nlhs nrhs))
				(list cond2 (make!-lesseq nlhs nrhs))))
			 (>=
			  (list (list cond1 (make!-greatereq nlhs nrhs))
				(list cond2 (make!-less nlhs nrhs)))))))))
	      (let* ((nlhs n1)
		     (nrhs (make!-times rhs d1)))
		(case (id (operator nfmla))
		  (= (list (list (make!-equation nlhs nrhs))))
		  (/= (list (list (make!-disequation nlhs nrhs))))
		  (t (let ((cond1 (make!-less d1 (make!-number-expr 0)))
			   (cond2 (make!-greatereq d1 (make!-number-expr 0))))
		       (case (id (operator nfmla))
			 (<
			  (list (list cond1 (make!-less nlhs nrhs))
				(list cond2 (make!-greatereq nlhs nrhs))))
			 (<=
			  (list (list cond1 (make!-lesseq nlhs nrhs))
				(list cond2 (make!-greater nlhs nrhs))))
			 (>
			  (list (list cond1 (make!-greater nlhs nrhs))
				(list cond2 (make!-lesseq nlhs nrhs))))
			 (>=
			  (list (list cond1 (make!-greatereq nlhs nrhs))
				(list cond2 (make!-less nlhs nrhs)))))))))))
	(if (is-division? rhs)
	    (let* ((n2 (args1 rhs))
		   (d2 (args2 rhs))
		   (nlhs (make!-times lhs d2))
		   (nrhs n2))
	      (case (id (operator nfmla))
		(= (list (list (make!-equation nlhs nrhs))))
		(/= (list (list (make!-disequation nlhs nrhs))))
		(t (let ((cond1 (make!-less d2 (make!-number-expr 0)))
			 (cond2 (make!-greatereq d2 (make!-number-expr 0))))
		     (case (id (operator nfmla))
		       (<
			(list (list cond1 (make!-less nlhs nrhs))
			      (list cond2 (make!-greatereq nlhs nrhs))))
		       (<=
			(list (list cond1 (make!-lesseq nlhs nrhs))
			      (list cond2 (make!-greater nlhs nrhs))))
		       (>
			(list (list cond1 (make!-greater nlhs nrhs))
			      (list cond2 (make!-lesseq nlhs nrhs))))
		       (>=
			(list (list cond1 (make!-greatereq nlhs nrhs))
			      (list cond2 (make!-less nlhs nrhs)))))))))
	    (list (list nfmla))))))

(defun poly-negate (fmla)
  (let ((lhs (args1 fmla))
	(rhs (args2 fmla)))
    (case (id (operator fmla))
      (= (make!-disequation lhs rhs))
      (/= (make!-equation lhs rhs))
      (< (make!-greatereq lhs rhs))
      (<= (make!-greater lhs rhs))
      (> (make!-lesseq lhs rhs))
      (>= (make!-less lhs rhs))
      (t (error "Poly-negate called with non-polynomial")))))
    

(defun lift-division (expr)
  (lift-division* expr))

(defmethod lift-division* (ex)
  ex)

(defmethod lift-division* ((ex application))
  (if (and (interpreted? (operator ex))
	   (memq (id (operator ex)) '(+ - * /)))
      (if (and (eq (id (operator ex)) '-)
	       (null (args2 ex)))
	  (let ((arg1 (lift-division* (args1 ex))))
	    (if (is-division? arg1)
		(make!-divides (make!-minus (args1 arg1))
			       (args2 arg1))
		ex))
	  (let* ((arg1 (lift-division* (args1 ex)))
		 (arg2 (lift-division* (args2 ex))))
	    (case (id (operator ex))
	      ((+ -)
	       (if (is-division? arg1)
		   (let ((n1 (args1 arg1))
			 (d1 (args2 arg1)))
		     (if (is-division? arg2)
			 (let ((n2 (args1 arg2))
			       (d2 (args2 arg2)))
			   (make!-divides
			    (let ((s1 (make!-times n1 d2))
				  (s2 (make!-times n2 d1)))
			      (if (eq (id (operator ex)) '+)
				  (make!-plus s1 s2)
				  (make!-difference s1 s2)))
			    (make!-times d1 d2)))
			 (make!-divides
			  (if (eq (id (operator ex)) '+)
			      (make!-plus n1 (make!-times arg2 d1))
			      (make!-difference n1 (make!-times arg2 d1)))
			  d1)))
		   (if (is-division? arg2)
		       (let ((n2 (args1 arg2))
			     (d2 (args2 arg2)))
			 (make!-divides
			  (if (eq (id (operator ex)) '+)
			      (make!-plus (make!-times arg1 d2) n2)
			      (make!-difference (make!-times arg1 d2) n2))
			  d2))
		       ex)))
	      (* (if (is-division? arg1)
		     (let ((n1 (args1 arg1))
			   (d1 (args2 arg1)))
		       (if (is-division? arg2)
			   (let ((n2 (args1 arg2))
				 (d2 (args2 arg2)))
			     (make!-divides
			      (make!-times n1 n2)
			      (make!-times d1 d2)))
			   (make!-divides (make!-times n1 arg2) d1)))
		     (if (is-division? arg2)
			 (let ((n2 (args1 arg2))
			       (d2 (args2 arg2)))
			   (make!-divides (make!-times arg1 n2) d2))
			 ex)))
	      (/ (if (is-division? arg1)
		     (let ((n1 (args1 arg1))
			   (d1 (args2 arg1)))
		       (if (is-division? arg2)
			   (let ((n2 (args1 arg2))
				 (d2 (args2 arg2)))
			     (make!-divides
			      (make!-times n1 d2)
			      (make!-times d1 n2)))
			   (make!-divides n1 (make!-times d1 arg2))))
		     (if (is-division? arg2)
			 (let ((n2 (args1 arg2))
			       (d2 (args2 arg2)))
			   (make!-divides n2 (make!-times arg1 d2)))
			 ex))))))
      ex))
	 
	 

(defmethod translate-to-rahd* ((ex application))
  (if (interpreted? (operator ex))
      (let ((op (id (operator ex))))
	(cond ((memq op '(+ * / < <= > >= =))
	       (let ((arg1 (translate-to-rahd* (args1 ex)))
		     (arg2 (translate-to-rahd* (args2 ex))))
		 (when (eq op '/)
		   (pushnew (list (list 'rahd::NOT (list '= arg2 0))) *rahd-typepreds* :test #'equal))
		 (list op arg1 arg2)))
	      ((eq op '/=)
	       (list 'rahd::NOT (list '=
				      (translate-to-rahd* (args1 ex))
				      (translate-to-rahd* (args2 ex)))))
	      ((eq op '-)
	       (if (tuple-expr? (argument ex))
		   (list op
			 (translate-to-rahd* (args1 ex))
			 (translate-to-rahd* (args2 ex)))
		   (list op 0 (translate-to-rahd* (argument ex)))))
	      ((eq op 'NOT)
	       (list 'rahd::NOT (translate-to-rahd* (args1 ex))))
	      (t (make-rahd-variable ex))))
      (make-rahd-variable ex)))

(defmethod translate-to-rahd* ((ex number-expr))
  (number ex))

(defmethod translate-to-rahd* ((ex name-expr))
  (assert (compatible? (type ex) *real*))
  (make-rahd-variable ex))

;;; Fall-through method - simply create a 
(defmethod translate-to-rahd* ((ex expr))
  (assert (compatible? (type ex) *real*))
  (make-rahd-variable ex))

(defmethod translate-to-rahd* (ex)
  (break "Why?"))

(defvar *rahd-typepredding* nil)

(defun make-rahd-variable (ex)
  (or (gethash ex *pvs-rahd-hash*)
      (let ((var (new-rahd-variable))
	    (tpreds (unless *rahd-typepredding*
		      (type-constraints ex))))
	(setf (gethash var *rahd-pvs-hash*) ex)
	(setf (gethash ex *pvs-rahd-hash*) var)
	(dolist (tpred tpreds)
	  (when (polynomial-formula?* tpred)
	    (let ((*rahd-typepredding* t))
	      (pushnew (list (translate-to-rahd* tpred))
		       *rahd-typepreds* :test #'equal))))
	var)))

(defun new-rahd-variable ()
  (let ((idstr (format nil "rr~d" (funcall *rahd-var-counter*))))
    (if (find-symbol idstr)
	(new-rahd-variable)
	(intern idstr))))
