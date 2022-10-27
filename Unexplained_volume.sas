%let estwindow=60;
%let lag=7;
%let gap=3; 
%let begdate=01jan1980;
%let enddate=30sep2022;
%let stocks_filter=shrcd in (10,11);
%let exch_filter=exchcd in (1,2,3,4);
%let dsevars=shrcd exchcd;
%let dsfvars = vol ret bid ask bidlo askhi shrout cfacpr cfacshr; /*CRSP stock file variables           */

               libname home '~'; 
 
                 options sasautos=('/wrds/wrdsmacros/', SASAUTOS) MAUTOSOURCE;
 
 
                  /* STAGE 1: MERGE CRSP STOCK AND EVENTS DATA                                         */
    
                  /* Merge CRSP stock (dsf) and event (dse) files into the output file named "CRSP_D"             */ 

 %CrspMerge(s=d,start=&begdate,end=&enddate,sfvars=&dsfvars,sevars=&dsevars,
            filters=&exch_filter and &stocks_filter);
            
            
                  /*   STAGE 2: CONSTRUCT UNEXPLAINED VOLUME           */
 Proc Sql;
   create view Market_Vol
/*        calculate market volatility as the sum of volatility of all stocks within day */
       as select a.date, sum(vol*cfacshr)
           as market_vol 
    from CRSP_d a 
    group by date
    order by date;
  
  create view Market_Return
/*   calculate market return as the average of return of all stock within day (equal-weighted-return) */
       as select a.date, avg(ret)
          as market_return 
    from CRSP_d a 
    group by date
    order by date;
 
         quit;

Data Standardize_Unexplained_Volume; merge  Market_Vol Market_Return;

Proc Sort Data=Standardize_Unexplained_Volume nodupkey; by date;run;


Data Standardize_Unexplained_Volume; set Standardize_Unexplained_Volume;
   by date;
/*    Divide return-variable into two seperate variable */
      ret_pos=(market_return>0)*abs(market_return);  
      ret_neg=(market_return<0 and not missing(market_return))*abs(market_return);
        run;
        
        
/*Create trading calendar based on the length of estimation window (estwindow), */
/*and the trading day gap between the end of estimation period and the date     */
/*of the actual unexplained volume calculation. Using trading calendar ensures  */
/* that the same number of trading days is used in calculations    */
Data _Caldates;
     merge Crsp.Dsi (keep=date rename=(date=estper_beg))
     Crsp.Dsi (keep=date firstobs=%eval(&estwindow) rename=(date=estper_end))
     Crsp.Dsi (keep=date firstobs=%eval(&estwindow+&gap+1));
     format estper_beg estper_end date date9.;
     if missing(estper_beg)=0 and missing(estper_end)=0 and missing(date)=0;
run;

proc sql noprint;
    create table Start as
    select a.date, abs(a.estper_beg-b.first_date) as dist, b.last_date format=date9.
    from _Caldates a, (
            select min(date) as first_date, max(date) as last_date
            from Standardize_Unexplained_Volume (where=(not missing(market_vol)))) b
    having dist=min(dist)
    order by date desc;
 
    select date format=8., last_date format=8. into: k_start,
                                                   : k_end
    from start (firstobs=1);
quit;

/*Starting and ending trading days for the rolling regressions module required     */
/*to calculate stock return volatility and standardized unexplained volume         */
%put 'Starting Date For Rolling Regressions '; %put %sysfunc(putn(&k_start,date9.));
%put 'Ending Date For Rolling Regressions ';   %put %sysfunc(putn(&k_end,date9.));
    
options nosource nonotes;
filename junk dummy; proc printto log = junk; run;

           %Macro REGS;
             %do k=&k_start %to &k_end;
              /*read the trading days for the beginning and the end of the estimation period*/
                data _Null_; set _Caldates (where=(date=&k));
                call symput('start',estper_beg);
                call symput('end',estper_end);
                run;
    
           proc reg data=Standardize_Unexplained_Volume noprint edf outest=params;
             where &start <=date <=&end;
              /*the overstatement of volume for NASDAQ securities to be captured by intercept*/
               model market_vol=ret_pos ret_neg;
               quit;
     
           data Params; set Params;
              date=&k; format date date9.;
               run;
             
           proc append base=Params_all data=Params;run;
              %end;
              %mend;
    
           %REGS;
           options source notes;
           
           proc printto;run;
    
Proc Sort Data=Params_all thread; by date;run;

Data Params_all;
set Params_all (rename=(ret_pos=pos_beta ret_neg=neg_beta));
drop market_vol;
run;

Data Suv;
     merge Standardize_Unexplained_Volume (in=a) Params_all;
     by date;
     predicted_vol=intercept+pos_beta*ret_pos+neg_beta*ret_neg;
     suv=(market_vol-predicted_vol)/_rmse_ ;
     
     if sum(_p_,_edf_)>=0.8*&estwindow and a;
     keep date market_return market_vol suv predicted_vol;
     label predicted_vol='Predicted Volume'
           suv='Standardized Unexplained Volume';
run;


                      /* STAGE 3: CONSTRUCT RETURN VOLATILITY */

                      /* Return Volatility is calculated as the standard deviation of returns within day */
proc means data=work.crsp_d noprint;
    class date;
    var ret;
    Output out=F1 std= volatility;   
run;

                    /* STAGE 4: CONSTRUCT BID-ASK SPREAD */
                    /* Market Bid-Ask Spread in Percentage is calculated as the average of bid-ask spreads in percentage within day   */

Data BA;
 set work.crsp_d;
 midpoint=coalesce(mean(ask,bid),mean(askhi,bidlo));
 baspread=coalesce(ask-bid, askhi-bidlo)/midpoint;
 run;


 proc means data=work.BA noprint;
    class date;
    var baspread;
    Output out=Bid_ask mean= bid_ask;   
run;

             /* Put Unexplained Trading Volume and Return Volatility into 1 file */
/* *************************************************************************************** */
Data combine;
merge suv F1 Bid_ask ;
by date;
keep volatility date suv bid_ask;
if nmiss(of suv date volatility bid_ask:) then delete;
run;
