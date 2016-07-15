%macro model_step(	libn=,
					outlibn=,
					dsn_var_sel=,
					dsn_ts_train=,
					dsn_ts_score=,
					outdsn=,
					ycol=,
					xcol=,
					y=,
					byvar=,
					time_var=
					);

/*==================================================================================*/
/* Incude statements */
/*==================================================================================*/

	PROC SORT data=&dsn_var_sel. out=&outlibn..t1(keep=&ycol &byvar &xcol) nodupkey;
		by &ycol &byvar &xcol;
	RUN;

	DATA _null_;
		call symputx("lastby", scan("&byvar",-1));
	RUN;

	DATA &outlibn..t1;
		retain id 0;
		set &outlibn..t1 end=e;
		by &ycol &byvar;
		if first.&lastby then id+1;
		if e then call symputx("lastid",id);
	RUN;

/*==================================================================================*/
/* Combine train and score */
/*==================================================================================*/

	DATA &outlibn..train_score;
		set &dsn_ts_train &dsn_ts_score;
		if (missing(&y)) then data_type=1;
		else data_type=0;
	RUN;

	PROC SORT data=&outlibn..train_score;
		by &byvar &time_var;
	RUN;

/*==================================================================================*/
/* Modeling */
/*==================================================================================*/

	%do i = 1 %to &lastid;
		PROC SQL noprint;
			select &xcol into : indeps separated  by ' ' from &outlibn..t1 where id=&i;
		QUIT;
		
		* BEGIN UNTESTED LOOPS - CALEB;
		%let j=1;
		%let var=%scan(&byvar,&j);
		%do %until(&var eq %nrstr( ));

			PROC HPREG data=&outlibn..train_score noprint;
				partition roleVar=data_type(train='0' test='1');
				by &var;
				id &var &time_var. &y;
				class time_dummy;
				model &y=time_dummy &indeps;
				*selection method=lasso;
				output out=&outlibn..r_p_&var pred=prediction;
			RUN;QUIT; 

			%let j=%eval(&j+1);
			%let var=%scan(&byvar,&j.);
		%end;

		PROC HPREG data=&outlibn..train_score noprint;
			partition roleVar=data_type(train='0' test='1');
			by &byvar;
			id &byvar &time_var. &y;
			class time_dummy;
			model &y=time_dummy &indeps;
			*selection method=lasso;
			output out=&outlibn..r_p_leaf pred=prediction;
		RUN;QUIT; 

		data &outlibn..reg_prediction;
			set 
				%let j=1;
				%let var=%scan(&byvar,&j);
				%do %until(&var eq %nrstr( ));
					
					&outlibn..r_p_&var
					%let j=%eval(&j+1);
					%let var=%scan(&byvar,&j.);

				%end;

				&outlibn..r_p_leaf;
		run;
		* END UNTESTED LOOPS - CALEB;

		* do not allow negative forecasts ;
		DATA &libn..&outdsn.;
			 set &outlibn..reg_prediction;
			 if ^missing(prediction) and prediction < 0 then do;
			  prediction = 0;
			 end;
		RUN; 
	%end;

/*==================================================================================*/
/* Delete intermediate files */
/*==================================================================================*/

	PROC DATASETS library=&outlibn memtype=data nolist;
		delete	t1
				train_score
				reg_prediction
				;
	RUN;QUIT;

%mend;
