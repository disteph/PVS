(in-package :pvs)

(defun herbrandize (fmlas)
  (herbrandize* fmlas nil nil))

(defmethod herbrandize* ((fmlas null) xs subst)
  (values nil xs subst))

(defmethod herbrandize* ((fmlas cons) xs subst)
  (multiple-value-bind (term xs1 subst1)
      (herbrandize* (car fmlas) xs subst)
    (multiple-value-bind (terms xs2 subst2)
	(herbrandize* (cdr fmlas) xs1 subst1)
      (values (cons term terms) xs2 subst2))))

(defmethod herbrandize* ((fmla negation) xs subst)
  (multiple-value-bind (term ys subst1)
      (skolemize* (args1 fmla) xs subst)
    (values (dp::mk-negation term) ys subst1)))

(defmethod herbrandize* ((fmla disjunction) xs subst)
  (multiple-value-bind (term1 xs1 subst1)
      (herbrandize* (args1 fmla) xs subst)
    (multiple-value-bind (term2 xs2 subst2)
	(herbrandize* (args2 fmla) xs1 subst1)
      (values (dp::mk-disjunction term1 term2) xs2 subst2))))

(defmethod herbrandize* ((fmla conjunction) xs subst)
  (multiple-value-bind (term1 xs1 subst1)
      (herbrandize* (args1 fmla) xs subst)
    (multiple-value-bind (term2 xs2 subst2)
	(herbrandize* (args2 fmla) xs1 subst1)
      (values (dp::mk-conjunction term1 term2) xs2 subst2))))

(defmethod herbrandize* ((fmla iff-or-boolean-equation) xs subst)
    (herbrandize* (expand-iff fmla) xs subst))

(defmethod herbrandize* ((fmla implication) xs subst)
 (multiple-value-bind (term1 xs1 subst1)
      (skolemize* (args1 fmla) xs subst)
    (multiple-value-bind (term2 xs2 subst2)
	(herbrandize* (args2 fmla) xs1 subst1)
      (values (dp::mk-implication term1 term2) xs2 subst2))))

(defmethod herbrandize* ((fmla expr) xs subst)
  (let ((term (dp::replace-by (top-translate-to-dc fmla)
			      subst)))
    (values term xs subst)))

(defmethod herbrandize* ((fmla forall-expr) xs subst)
  (let* ((fmla (relativize-quantifier fmla))
	 (bndngs (bindings fmla)))
    (unless (safe-to-skolemize? bndngs)
      (throw 'not-skolemizable nil))
    (let ((*bound-variables* (append bndngs *bound-variables*)))
      (declare (special *bound-variables*))
      (let ((assocs (mapcar #'(lambda (bndng)
				 (cons (top-translate-to-dc bndng)
				       (mk-new-skofun bndng xs)))
		      bndngs)))
	(herbrandize* (expression fmla) xs (append assocs subst))))))

(defmethod herbrandize* ((fmla exists-expr) xs subst)
  (let* ((fmla (relativize-quantifier fmla))
	 (bndngs (bindings fmla)))
    (let ((*bound-variables* (append bndngs *bound-variables*)))
      (declare (special *bound-variables*))
      (let ((assocs (mapcar #'(lambda (bndng)
				(cons (top-translate-to-dc bndng)
				      (mk-new-var bndng)))
		      bndngs)))
	(herbrandize* (expression fmla)
		      (union (mapcar #'cdr assocs) xs)
		      (append assocs subst))))))
	
(defmethod skolemize* ((fmla expr) xs subst)
  (let ((term (dp::replace-by (top-translate-to-dc fmla) subst)))
    (values term xs subst)))

(defmethod skolemize* ((fmla negation) xs subst)
  (multiple-value-bind (term xs1 subst1)
      (herbrandize* (args1 fmla) xs subst)
    (values (dp::mk-negation term) xs1 subst1)))

(defmethod skolemize* ((fmla disjunction) xs subst)
  (multiple-value-bind (term1 xs1 subst1)
      (skolemize* (args1 fmla) xs subst)
    (multiple-value-bind (term2 xs2 subst2)
	(skolemize* (args2 fmla) xs1 subst1)
      (values (dp::mk-disjunction term1 term2) xs2 subst2))))

(defmethod skolemize* ((fmla conjunction) xs subst)
  (multiple-value-bind (term1 xs1 subst1)
      (skolemize* (args1 fmla) xs subst)
    (multiple-value-bind (term2 xs2 subst2)
	(skolemize* (args2 fmla) xs1 subst1)
      (values (dp::mk-conjunction term1 term2) xs2 subst2))))

(defmethod skolemize* ((fmla iff-or-boolean-equation) xs subst)
    (skolemize* (expand-iff fmla) xs subst))

(defmethod skolemize* ((fmla implication) xs subst)
  (multiple-value-bind (term1 xs1 subst1)
      (herbrandize* (args1 fmla) xs subst)
    (multiple-value-bind (term2 xs2 subst2)
	(skolemize* (args2 fmla) xs1 subst1)
      (values (dp::mk-implication term1 term2) xs2 subst2))))

(defmethod skolemize* ((fmla forall-expr) xs subst)
 (let* ((fmla (relativize-quantifier fmla))
	 (bndngs (bindings fmla)))
    (let ((*bound-variables* (append bndngs *bound-variables*)))
      (declare (special *bound-variables*))
      (let ((assocs (mapcar #'(lambda (bndng)
				(cons (top-translate-to-dc bndng)
				      (mk-new-var bndng)))
		      bndngs)))
	(skolemize* (expression fmla)
		    (union (mapcar #'cdr assocs) xs)
		    (append assocs subst))))))
		      
(defmethod skolemize* ((fmla exists-expr) xs subst)
 (let* ((fmla (relativize-quantifier fmla))
	 (bndngs (bindings fmla)))
    (unless (safe-to-skolemize? bndngs)
      (throw 'not-skolemizable nil))
    (let ((*bound-variables* (append bndngs *bound-variables*)))
      (declare (special *bound-variables*))
      (let ((assocs (mapcar #'(lambda (bndng)
				 (cons (top-translate-to-dc bndng)
				       (mk-new-skofun bndng xs)))
		      bndngs)))
	(skolemize* (expression fmla) xs (append assocs subst))))))

(defun safe-to-skolemize? (bndngs)
  (every #'(lambda (bndng)
		   (nonempty? (type bndng)))
	 bndngs))

(defun relativize-quantifier (fmla)
  (lift-predicates-in-quantifier fmla
				 (list *naturalnumber* *integer*)))

(defun expand-iff (fmla)
  (make!-conjunction (make!-implication (args1 fmla) (args2 fmla))
		     (make!-implication (args2 fmla) (args1 fmla))))

(defun mk-new-vars (bndngs)
  (mapcar #'mk-new-var bndngs))

(defun mk-new-var (bndng)
  (let ((id (gentemp (makesym "~a?" (id bndng)))))
    (dp::mk-new-variable id nil)))

(defun mk-new-skofun (bndng xs)
  (let* ((id (gentemp (makesym "~a!" (id bndng))))
	 (sym (dp::mk-new-constant id nil)))
    (if (null xs) sym
	(dp::mk-term (cons sym xs)))))
