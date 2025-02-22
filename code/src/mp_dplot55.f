  
      program mp_dplot55

C *************************************************************************************
C *****
C ***** %%%%%%%%%%%%%%%%         program MP_DPLOT  1.55        %%%%%%%%%%%%%%%%%%%%%%%%%%%%
C *****
C *****   calculates the pair distribution functions (PDF) for simulated supercell data
C *****
C**********          Copyright (C) 2023  Jiri Kulda, Grenoble/Prague          **********
C**  
C** This file is part MP_TOOLS developed and maintained by Jiri Kulda <jkulda@free.fr>
C**
C**  MP_TOOLS are free software: you can use it, redistribute it and/or modify it 
C**  under the terms of the GNU General Public License as published by the Free Software 
C**  Foundation, either version 3 of the License, or (at your option) any later version, 
C**  for details see <https://www.gnu.org/licenses/>
C**
C**  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
C**  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
C**  See the GNU General Public License for more details.
C**
C ***** %%%%%%%%%%%%%%%%         program MP_DPLOT  1.55        %%%%%%%%%%%%%%%%%%%%%%%%%%%%
C *****
C ***** Ver. 1.1 The correlation is asymmetric: N_HSUM random cell against the complete supercell
C ***** Ver. 1.2 the whole supercell is read into memory once for ever
C ***** Ver. 1.21 the correlation is symmetric N_HSUM random cells against N_HSUM random cells
C *****
C ***** Ver. 1.31 between two delayed snapshot frame uses the 1.21 symmetric algorithm
C ***** Ver. 1.31 now the delay may be 0, so 1.31 replaces also ver. 1.21 and will override it
C *****
C ***** Ver. 1.32 the IDOM dialog moved after reading first input file
C ***** Ver. 1.32 the TIME_LOOP replaces the slice_loop
C ***** Ver. 1.32 normalization of correlation functions by true number of active cells n_norm = 45**3
C ***** 
C ***** Ver. 1.33 the reference snapshot and the first one in the time-series defined independently
C ***** Ver. 1.33 hence instantaneous (lag 0) correlations can be calculated explicitly
C ***** 
C ***** Ver. 1.4   - flexible cell structure
C *****            - use of auxiliary <file_title.par> file (correlation pairs etc.)
C ***** Ver. 1.41  - corrected inconsistency in output <rdf>.txt file name
C *****            - correct histogram identification by j_hist_type
C ***** 
C ***** Ver. 1.42  - lighter & parallelied version (no correlation histograms, no IDOM)
C *****            - integrates the PGPLOT graphics of mp_rplot.f
C *****           - only PDF
C *****           - for correlation histograms (refer to mp_corr)
C *****           - modified .PAR file format, consequent .LOG
C ***** 
C ***** Ver. 1.50  - start of new series (identical to mp_pdf 1.42) as MP_PDF
C ***** 
C ***** Ver. 1.51  - all data arrays allocatable, no predefined array size limits
C *****           - supercell format in .PAR
C *****            - number of correlation pairs read from .PAR (don't use ver. 1.50!)
C *****
C ***** Ver 1.53  - record length 4096, all data 32bit length
C *****            - at_mass is saved as at_veloc(4,j,k)
C *****            - at_charge is saved as at_pos(4,j,k)
C *****           - CELL and QUICK data type (BULK not eligible for PDF)
C *****            - secondary sampling volume clipped for highly anisotropic or 2D supercells
C *****
C ***** 
C ***** Ver 1.54  - NAMELIST I/O for .PAR files and .DAT headers implemented 
C *****           - PNG driver for PGPLOT included
C *****           
C ***** 
C ***** file name convention:
C *****     <master_file>_n<snapshot number>.dat
C *****     example: H05_10K_n0001.dat from H05_10K.txt
C *****
C ***** indexing convention: supercell(u,v,w) = at_ind(j,k,l) = supercell(j_pos,j_row,j_layer)
C ***** record numbers are directly related to cell positions and atom types
C *****    jrec = 1+nsuper*(jat-1)+nlayer*(at_ind(3)-1)+nrow*(at_ind(2)-1)+at_ind(1)
C *****            1 going for the header record
C *****
C ***** atom positions are converted from reduced lattice coordinates (x) to real space distances
C ***** 
  
      use omp_lib
      
CC      use mp_nopgplot          ! uncomment when not able to use PGPLOT, compile and link together with the module mp_nopgplot.f

      integer,parameter :: l_rec  =  1024        !record length in real(4)
      real,parameter    :: pi = 3.14159

      character(4),allocatable  ::  at_name_par(:),at_label(:)
      character(10),allocatable ::  dom_ind(:)

      integer,allocatable ::  i_dom(:,:,:,:,:),i_dom_p(:,:,:,:),i_dom_out(:,:),ind(:,:,:),mask(:)

      real,allocatable :: displ_field(:,:,:,:,:,:),displ_field1(:,:,:,:,:,:),displ_norm(:,:,:,:,:),displ_norm_tot(:,:)
      real,allocatable :: vel_field(:,:,:,:,:,:),vel_norm(:,:,:,:,:),vel_field1(:,:,:,:,:,:),vel_norm1(:,:,:,:,:)
      real,allocatable :: polar(:,:,:,:,:),polar_tot(:,:),pol_norm(:,:,:,:),pol_norm_tot(:)
      real,allocatable :: at_base(:,:),at_charge(:),at_charge1(:),displ_plot(:,:,:),displ_vect(:,:,:)
    
      real     ::  c_min,c_max,filter_fwhm,p_size,res(3),pol(3),res2,charge_mom_c(3),charge_mom_s(3),charge_mom_cell(3)
      real     ::  e1_norm(3),e2_norm(3),ev_norm(3),x1,y1,x2,y2
      
      character(4)   :: c_int(2),c_fil(2),version,head,atom
      character(10)  :: pg_out,string,section,c_date,c_time,c_zone,c_jt,c_slice,c_mode,c_jfile,at_name
      character(16)  :: sim_type_par,data_type,string16,wedge_label,filter_name,c_e1(3),c_e2(3),c_x,c_y
      character(40)  :: subst_name,file_master,file_inp,file_out,time_stamp,int_mode,x_file_name
      character(60)  :: file_dat,file_dat_t0,file_res,file_ps,file_log,line
      character(128) :: cwd_path,plot_title
      character(l_rec):: header_record
      
      logical ::  nml_in,found_txt,found_ps,t_single

      integer(8) ::  n_in,n_out,n_inbox,n_outbox,n_pdf_range(3),n_mc,n_mc_max,n_norm
      integer ::  j_proc,proc_num,proc_num_in,j_name,jm,j1m,j2m,j_mode,mode
      integer ::  i_start,i_end,j_part(4),n_step,nfile_step,n_hsum,n_h,j_head_in,j_verb,n_tot,n_head,j_auto,j_frame,n_slice,j_atom
      integer ::  i,j,k,m,i2,i3,ii,jj,at,i_rec,ind_rec,nrec,ncell,nrow,nlayer,nsuper,nfile,nfile_t0,nfile_min,nfile_max,jfile
      integer ::  j1,j2,j_plane,j_grid,j_logsc,j_ps,j_op,j_tot,j_txt,i_time(8),j_cycle,i_shift,j_adv,n_shift,j_shift,j_slice,j_sign,jt,jt0,jt_max
      integer ::  at_no,at_ind(3),at_ind2(3),d_ind(3),n_dom,j_base(3),n_plot,e1(3),e2(3),ev(3),e_slice(3),ind_c,n_x,n_y
      integer ::  jat,j_edit,j_mask,ifile,ifile0,jfil_step,jint,jint2,n_atom,sc_c2,sc_c1,ier,ios
      integer ::  j_weight,j_xray
      
C **** the following variables MUST have the following type(4) or multiples because of alignement in the binary output file
      character(4),allocatable :: at_name_out(:)
      integer(4),allocatable   :: nsuper_r(:),at_ind_in(:),at_ind_file(:,:,:,:,:)

      real(4),allocatable ::  at_occup_r(:)
      real(4),allocatable,target ::  at_pos_in(:),at_pos1_in(:),at_vel_in(:),at_vel1_in(:)
      real,pointer        :: at_pos_file(:,:,:,:,:),at_pos1_file(:,:,:,:,:),at_vel_file(:,:,:,:,:),at_vel1_file(:,:,:,:,:)
      
      character(16)  :: sim_type,dat_type,input_method,file_par,dat_source
      integer(4)     :: n_row(3),n_at,n_eq,j_force,j_shell_out,n_traj,n_cond,n_rec,n_tot_in,idum
      real(4)        :: rec_zero(l_rec),t_ms,t0,t_dump,t_step,a_par(3),angle(3),temp

      namelist /data_header_1/sim_type,dat_type,input_method,file_par,subst_name,t_ms,t_step,t_dump,temp,a_par,angle,
     1    n_row,n_atom,n_eq,n_traj,j_shell_out,n_cond,n_rec,n_tot,filter_name,filter_fwhm             !scalars & known dimensions
      namelist /data_header_2/at_name_out,at_base,at_occup_r,nsuper_r           !allocatables
     
      namelist /mp_gen/ j_verb,j_proc       
      namelist /mp_out/ j_weight,j_logsc,j_txt,p_size,j_grid,pg_out       
                          !general rule: namelists of tools should only contain their local parameters
                          !what is of global interest they should pass into data_header
      
C *** PGPLOT variables 
      INTEGER   PGBEG,PGOPEN
      INTEGER   MXI, MXJ
      PARAMETER (MXI=21, MXJ=21)
      INTEGER   L, C1, C2,CI, NC
      REAL      F(MXI,MXJ),CR,CG,CB,CH,CL,CS
      REAL      FMIN,FMAX,TR(6), CONTRA, BRIGHT, C, S, ALEV(1),BLANK,SCALE,SIZE
      CHARACTER*16 VAL 


C *** Set the coordinate transformation matrix: world coordinate = pixel number.
        TR(1) = 0.0
        TR(2) = 1.0
        TR(3) = 0.0
        TR(4) = 0.0
        TR(5) = 0.0
        TR(6) = 1.0


C ********************* Initialization *******************************      

      write(*,*) '*** Program MP_PDF 1.55 ** Copyright (C) Jiri Kulda (2019,2021,2022) ***'
      write(*,*)'      *** for the moment only MonteCarlo integration is available *** '
      write(*,*)
      
C ********************* Get a time stamp and open a .LOG file *******************************
      call getcwd(cwd_path)
      call date_and_time(c_date,c_time,c_zone,i_time)
      write(time_stamp,110) c_date(1:4),c_date(5:6),c_date(7:8),c_time(1:2),c_time(3:4),c_time(5:6)
110    format(a,'/',a,'/',a,' ',a,':',a,':',a)      
      write(file_log,111) trim(c_date)
111   format('mp_tools_',a,'.log')
      inquire(file=file_log,exist=found_txt)
      if(found_txt)then
        open (9,file=file_log,position='append')
      else
        open (9,file=file_log)
      endif

      write(9,*) 
      write(9,*) 
      write(9,*) trim(time_stamp),'  MP_DPLOT 1.55  ',trim(cwd_path)
      write(9,*) 
      
C *** Generate data file access
      write(*,*) 'Input data file_master: '
      read(*,*) file_master 
            
      write(*,*) 'Read data files number min, max (0 0 no numbers, single file): '
      read(*,*)   nfile_min,nfile_max
      nfile_step = 1
      t_single = nfile_min==0.and.nfile_max==0    

      if(t_single)then
        nfile_min = 1    !for conformity with loop control conventions
        nfile_max = 1
        nfile_step = 1
      endif
      
      nfile = ((nfile_max-nfile_min)/nfile_step)+1
      
      if(t_single)then
        write(file_dat_t0,'("./data/",a,".dat")') trim(file_master)
      else
        if(nfile_min<=9999) then
          write(file_dat_t0,'("./data/",a,"_n",i4.4,".dat")') trim(file_master),nfile_min
        elseif(nfile_min>=10000) then
          write(string,'(i8)') nfile_min
          file_dat_t0 = './data/'//trim(file_master)//'_n'//trim(adjustl(string))//'.dat'
        endif
      endif

      open (1,file=file_dat_t0,status ='old',access='direct',action='read',form='unformatted',recl=4*l_rec,iostat=ios)
      if(ios.ne.0) then
        write(*,*) 'File ',trim(file_dat_t0),' not found! Stop execution.'
        stop
      endif
      
C *** Read the header record 

      i_rec = 1         
      read(1,rec=i_rec) header_record
      head = header_record(1:4)
      call up_case(head)
      if(head == 'MP_T') then      !new structure with namelist
        nml_in = .true.
        read(1,rec=i_rec) dat_source,version,string16
        read(string16,*) n_head
        write(*,*)    'Input data:  ',dat_source,version,n_head
        i_rec = i_rec+1                 
        read(1,rec=i_rec) header_record
        read(header_record,nml=data_header_1)  
        t0 = t_dump
CC        write(*,nml=data_header_1)
      else
        write(*,*) 'header record wrong or missing'
        write(*,*) trim(header_record)
        stop
      endif 
      
      if(trim(input_method)/='CELL') then
        write(*,*) 'ERROR: the present data were produced by the ',trim(input_method),' method,'
        write(*,*) 'while direct space mapping works with the CELL data only.'
        stop
      endif

      allocate(at_name_out(n_atom),at_occup_r(n_atom),nsuper_r(n_atom))
      allocate(at_label(n_atom),at_name_par(n_atom),at_base(n_atom,3),at_charge(n_atom),at_charge1(n_atom))

      i_rec = i_rec+1                 
      read(1,rec=i_rec) header_record
      close(1)
      read(header_record,nml=data_header_2)
C      write(*,*) 'Header done'    

C **** Read the auxiliary file <file_par.par> with structure parameters, atom names and further info
C     write(*,*) 'Parameter file name (.par to be added) (confirm or type other name): ', file_par
C     read(*,*) file_par

      file_inp = trim(file_par)//'.par'
      write(*,*) 'Parameter file name: ', file_inp

      open(4,file=file_inp,action='read',status ='old',iostat=ios)
      if(ios.ne.0) then
        write(*,*) 'File ',trim(file_inp),' not found! Stop execution.'
        stop
      endif

      write(9,*) 'Read the parameter file:  ',trim(file_inp)

      read(4,nml=mp_gen)
      rewind(4)
      read(4,nml=mp_out)
      rewind(4)

CC      write(*,*) 'Sim_type, dat_type, input method: ',sim_type,dat_type,input_method    
      j_adv = 2
      n_shift = 10
      at_name_par = at_name_out  
      close(4)

C *** write overview of atom data
      write(*,*)
      write(*,*) 'Substance name: ',subst_name    
      write(*,*) 'Atoms from ',trim(file_inp)
      do j=1,n_atom
        write(*,'(5x,i2,5x,a4,3f8.4,2x,f8.4)')  j,at_name_par(j),at_base(j,:),at_occup_r(j)
        write(9,'(5x,a4,3f8.4,2x,f8.4)')  at_name_par(j),at_base(j,:),at_occup_r(j)
      enddo

C *** define references for lattice search  
C     nrow = n_row(1)
      nsuper = n_row(1)*n_row(2)*n_row(3)

C *** Allocate and clear the histogram arrays for accumulation across several snapshots         
C     allocate (at_ind_file(4,n_row(1),n_row(2),n_row(3),jat),at_ind_in(4*n_tot))

      allocate(at_pos_in(4*n_tot),at_vel_in(4*n_tot))
      allocate(displ_field(3,n_row(1),n_row(2),n_row(3),n_atom,nfile),displ_norm(n_row(1),n_row(2),n_row(3),n_atom,nfile),displ_norm_tot(n_atom,nfile))
      allocate(vel_field(3,n_row(1),n_row(2),n_row(3),n_atom,nfile),vel_norm(n_row(1),n_row(2),n_row(3),n_atom,nfile))
      allocate(i_dom(n_row(1),n_row(2),n_row(3),n_atom,nfile),i_dom_p(n_row(1),n_row(2),n_row(3),nfile))
      allocate(polar(3,n_row(1),n_row(2),n_row(3),nfile),pol_norm(n_row(1),n_row(2),n_row(3),nfile),polar_tot(3,nfile),pol_norm_tot(nfile))
      if(j_shell_out==1) then 
        allocate(at_pos1_in(4*n_tot),at_vel1_in(4*n_tot),displ_field1(3,n_row(1),n_row(2),n_row(3),n_atom,nfile))
        allocate(vel_field1(3,n_row(1),n_row(2),n_row(3),n_atom,nfile),vel_norm1(n_row(1),n_row(2),n_row(3),n_atom,nfile))
      endif

 			write(*,*) 'Displacement domain type (0 = NONE, 1=[100], 2=[110], 3= 111])?'
 			read(*,*) n_dom		!displacement domain type (1=[100], 2=[110], 3= 111])
 			if(n_dom==0) i_dom = 1
 			    
CCC *** calculate the domain segment number - new convention different from MD_TOOLS
C
C			i_dom = 0																		!if n_dom = 0 nothing happens
C      do ii = 1,3
C      	pos_inp(ii) = at_pos_c(i,ii)-x_pos(jat,ii)
C      	pos_inp(ii) = pos_inp(ii)-nint(pos_inp(ii))
C      enddo
C			
C			if(n_dom.eq.1) then
C				i_dom = maxloc((abs(pos_inp)),dim=1)
CC					write(*,*) 'maxloc',i_dom
C				if(pos_inp(i_dom).gt.0.) i_dom = i_dom+3
C			else if (n_dom.eq.2) then
C				ii = minloc((abs(pos_inp)),dim=1)
CC					write(*,*) 'minloc',ii
C				i2 = ii+1
C				if(i2.gt.3) i2 = i2-3
C				i3 = ii+2
C				if(i3.gt.3) i3= i3-3
C				i_dom = mod(ii,3)*4+(sign(1.,pos_inp(i2))+1)+(sign(1.,pos_inp(i3))+1)/2 +1
C			else if (n_dom.eq.3) then
C				i_dom = 1
C				do ii=1,3
C					i_dom = i_dom+2**(ii-1)*(sign(1.0,pos_inp(ii))+1.)/2.
C				enddo 
C			endif

      jt0 = 1
      jt = 0

      file_loop: do ifile=nfile_min,nfile_max,nfile_step                  
        jt = jt+1
C ***  open the t0 file (binary MD snapshot file)
        if(t_single)then
          write(file_dat,'(a,".dat")') trim(file_master)
        else
          if(nfile_min<=9999) then
            write(file_dat,'(a,"_n",i4.4,".dat")') trim(file_master),nfile_min+(ifile-nfile_min)*nfile_step
          elseif(nfile_min>=10000) then
            write(string,'(i8)') nfile_min+(ifile-nfile_min)*nfile_step
            file_dat = trim(file_master)//'_n'//trim(adjustl(string))//'.dat'
          endif
        endif

C       write(*,*)
C       write(*,*)'input: ',file_dat
        write(9,*)'input: ',file_dat

        open(1,file='./data/'//file_dat,status ='old',access='direct',action='read',form='unformatted',recl=4*l_rec,iostat=ios)
        if(ios.ne.0) then
          write(*,*) 'File ',trim(file_dat),' not opened! IOS =',ios
          write(*,*) 'Skip(1), stop execution(0)?'
          read(*,*) jj
          if(jj==1) exit file_loop
          if(jj==0) stop
        endif

        i_rec = n_head+n_rec      !skipping at_ind
      
        do j=1,n_rec-1                    ! read CORE data
          i_rec = i_rec+1
          read(1,rec=i_rec) at_pos_in((j-1)*l_rec+1:j*l_rec)      
        enddo  
        i_rec = i_rec+1
        read(1,rec=i_rec) at_pos_in((n_rec-1)*l_rec+1:4*n_tot)  
        
        if(n_traj==1) then
          do j=1,n_rec-1                    ! read CORE data
            i_rec = i_rec+1
            read(1,rec=i_rec) at_vel_in((j-1)*l_rec+1:j*l_rec)      
          enddo  
          i_rec = i_rec+1
          read(1,rec=i_rec) at_vel_in((n_rec-1)*l_rec+1:4*n_tot) 
        endif 
        
        if(j_shell_out==1) then           ! read SHELL data
          i_rec = i_rec+(n_traj-1)*n_rec      !skip possible velocities & forces
          do j=1,n_rec-1
            i_rec = i_rec+1
            read(1,rec=i_rec) at_pos1_in((j-1)*l_rec+1:j*l_rec)      
          enddo  
          i_rec = i_rec+1
          read(1,rec=i_rec) at_pos1_in((n_rec-1)*l_rec+1:4*n_tot)  
        endif        

        if(n_traj==1) then
          do j=1,n_rec-1                    ! read CORE data
            i_rec = i_rec+1
            read(1,rec=i_rec) at_vel1_in((j-1)*l_rec+1:j*l_rec)      
          enddo  
          i_rec = i_rec+1
          read(1,rec=i_rec) at_vel1_in((n_rec-1)*l_rec+1:4*n_tot) 
        endif 
        
        close(1)

        at_pos_file(1:4,1:n_row(1),1:n_row(2),1:n_row(3),1:n_atom) => at_pos_in(:)
        at_vel_file(1:4,1:n_row(1),1:n_row(2),1:n_row(3),1:n_atom) => at_vel_in(:)
        vel_field(:,:,:,:,:,jt) = at_vel_file(1:3,:,:,:,:)

        if(j_shell_out==1) then
          at_pos1_file(1:4,1:n_row(1),1:n_row(2),1:n_row(3),1:n_atom) => at_pos1_in(:)
          at_vel1_file(1:4,1:n_row(1),1:n_row(2),1:n_row(3),1:n_atom) => at_vel1_in(:)
          vel_field1(:,:,:,:,:,jt) = at_vel1_file(1:3,:,:,:,:)
        endif

C       write(*,*) 'n_atom,n_row',n_atom,n_row

C       do
C         write(*,*) 'jat,i,j,k?'
C         read(*,*) jat,i,j,k
C         write(*,*) 'Core:', at_pos_file(:,i,j,k,jat)
C         write(*,*) 'Shell:', at_pos1_file(:,i,j,k,jat)
C       enddo
          
        do jat=1,n_atom
          do k=1,n_row(3)    
            do j=1,n_row(2)    
              do i=1,n_row(1)
                jj = 1 
                res2 = .0
                res = at_pos_file(1:3,i,j,k,jat)-at_base(jat,:)
                res = res-nint(res)
                displ_field(:,i,j,k,jat,jt) = res
                res2 = dot_product(res,res)
C                 jj = jj+2**(3-ii)*(sign(1.0,res)+1.)/2.

                if(n_dom==1) then
                  jj = maxloc((abs(res)),dim=1)
C					write(*,*) 'maxloc',i_dom
                  if(res(jj).gt.0.) jj = jj+3
                else if (n_dom==2) then
                  ii = minloc((abs(res)),dim=1)
C					write(*,*) 'minloc',ii
                  i2 = ii+1
                  if(i2.gt.3) i2 = i2-3
                  i3 = ii+2
                  if(i3.gt.3) i3= i3-3
                  jj = mod(ii,3)*4+(sign(1.,res(i2))+1)+(sign(1.,res(i3))+1)/2 +1
                else if (n_dom==3) then
                  jj = 1
                  do ii=1,3
                    jj = jj+2**(ii-1)*(sign(1.0,res(ii))+1.)/2.
                  enddo 
                endif

                if(j_shell_out==1) then
                  res = at_pos1_file(1:3,i,j,k,jat)-at_base(jat,:)
                  res = res-nint(res)
                  displ_field1(:,i,j,k,jat,jt) = res
                endif        
                i_dom(i,j,k,jat,jt) = jj
                displ_norm(i,j,k,jat,jt) = sqrt(res2)   !displacement magnitude is calculated for CORES only
              enddo
            enddo   
          enddo   
        enddo 

        do jat=1,n_atom
          displ_norm_tot(jat,jt) = sum(displ_norm(:,:,:,jat,jt))/nsuper
        enddo
C       if(j_verb==1) write(*,*) 'jt,displ_norm_tot(:,jt)',jt,displ_norm_tot(:,jt)
        
C ***  calculate nominal unit cell electric polarisation for regularly occupied lattice
        if(ifile==nfile_min.and.sum(at_occup_r)/n_atom==1.) then
          at_charge = at_pos_file(4,1,1,1,:)          
          if(j_verb==1) then  
            write(*,*) 'Atom (core) charges',at_charge, 'confirm or type new values'
            read(*,*) at_charge
          endif
 
          if(j_shell_out==1) then
            at_charge1 = at_pos1_file(4,1,1,1,:) 
            if(j_verb==1) then  
              write(*,*) 'Shell charges',at_charge1, 'confirm or type new values'
              read(*,*) at_charge1
            endif
          endif 

          charge_mom_c = 0.
          charge_mom_s = 0.
          do jat=1,n_atom                       
            charge_mom_c = charge_mom_c + at_charge(jat)*at_base(jat,:)          !core   
            if(j_shell_out==1) charge_mom_s = charge_mom_s + at_charge1(jat)*at_base(jat,:)         !shell
          enddo
          charge_mom_cell = charge_mom_c+charge_mom_s 
          if(j_shell_out==0) then
            write(*,*) 'Static unit cell dipole moment:',charge_mom_c     
          else
            write(*,*) 'Static unit cell dipole moment: cores ',charge_mom_c
            write(*,*) '                                shells',charge_mom_s
            write(*,*) '                                total ',charge_mom_cell
          endif
          write(*,*)
        endif 

C ***  calculate electric polarisation of each unit cell
        do k=1,n_row(3)    
          do j=1,n_row(2)    
            do i=1,n_row(1)
              charge_mom_c = 0.
              charge_mom_s = 0.
              do jat=1,n_atom                       
C               charge_mom_c = charge_mom_c + at_charge(jat)*displ_field(:,i,j,k,jat,jt)          !core   
C               if(j_shell_out==1) charge_mom_s = charge_mom_s + at_charge1(jat)*displ_field1(:,i,j,k,jat,jt)        !shell
                charge_mom_c = charge_mom_c + at_pos_file(4,i,j,k,jat)*displ_field(:,i,j,k,jat,jt)          !core   !use true local charges
                if(j_shell_out==1) charge_mom_s = charge_mom_s + at_pos1_file(4,i,j,k,jat)*displ_field1(:,i,j,k,jat,jt)        !shell
              enddo

C              polar(:,i,j,k,jt) = charge_mom_c+charge_mom_s-charge_mom_cell
              pol = charge_mom_c+charge_mom_s
              polar(:,i,j,k,jt) = pol
              pol_norm(i,j,k,jt) = norm2(pol)

C *** calculate the domain (quadrant) number for polar(ization)
              if(n_dom==1) then
                jj = maxloc((abs(pol)),dim=1)
C					write(*,*) 'maxloc',i_dom
                if(pol(jj).gt.0.) jj = jj+3
              else if (n_dom==2) then
                ii = minloc((abs(pol)),dim=1)
C					write(*,*) 'minloc',ii
                i2 = ii+1
                if(i2.gt.3) i2 = i2-3
                i3 = ii+2
                if(i3.gt.3) i3= i3-3
                jj = mod(ii,3)*4+(sign(1.,pol(i2))+1)+(sign(1.,pol(i3))+1)/2 +1
              else if (n_dom==3) then
                jj = 1
                do ii=1,3
                  jj = jj+2**(ii-1)*(sign(1.0,pol(ii))+1.)/2.
                enddo 
              endif

C             jj = 1
C             do ii=1,3
C                jj = jj+2**(3-ii)*(sign(1.0,pol(ii))+1.)/2.
CC                jj = jj+2**(3-ii)*(sign(1.0,charge_mom_c(ii))+1.)/2.
C             enddo  
              i_dom_p(i,j,k,jt) = jj        
            enddo
          enddo   
        enddo  
        
        do i=1,3
          polar_tot(i,jt) = sum(polar(i,:,:,:,jt))
        enddo
        polar_tot(:,jt) = polar_tot(:,jt)/nsuper
        pol_norm_tot(jt) = norm2(polar_tot(:,jt))
C       if(j_verb==1) write(*,*) 'jt,polar_tot(:,jt),pol_norm_tot(jt)',jt,polar_tot(:,jt),pol_norm_tot(jt)
      enddo file_loop

      jt_max = jt   ! jt_max = 1 means a single explicit JT while t_single means absence of JT numbers
      j_ps = 0
      j_sign = 1
      

CCC *** Polarisation domains:
CC         type {1 0 0}: 1 = [-1 0 0], 2 = [0 -1 0], 3 = [0 0 -1], 4 = [1 0 0], 5 = [0 1 0], 6 = [0 0 1]
CC
CC         type {1 1 0}: 1 = [-1 -1 0],   2 = [-1 1 0],  3 = [1 -1 0],  4 = [1 1 0], 
CC                       5 = [0 -1 -1],   6 = [0 -1 1],  7 = [0 1 -1],  8 = [0 1 1], 
CC                       9 = [-1  0 -1], 10 = [1 0 -1], 11 = [-1 0 1], 12 = [1 0 1]
CC
CC         type {1 1 1}: 1 = [-1 -1 -1], 2 = [1 -1 -1], 3 = [-1 1 -1], 4 = [1 1 -1],        !binary code from left: take the -1 for 0 & add +1
CC                       5 = [-1 -1  1], 6 = [1 -1  1], 7 = [-1 1  1], 8 = [1 1  1]

      select case(n_dom)      !n_dom becomes the number of possible domains
        case(0)
          n_dom = 1
        case(1)
          n_dom = 6
        case(2)
          n_dom = 12
        case(3)
          n_dom = 8
      end select

      allocate(dom_ind(n_dom),mask(n_dom))

      select case(n_dom)      !n_dom becomes the number of possible domains
        case(1)
          dom_ind = ''
        case(6)
          dom_ind = (/'[-1 0 0]','[ 0-1 0]','[ 0 0-1]','[ 1 0 0]','[ 0 1 0]','[ 0 0 1]'/)
        case(12)
          dom_ind = (/'[-1-1 0]','[-1 1 0]','[ 1-1 0]','[ 1 1 0]','[ 0-1-1]','[ 0-1 1]','[ 0 1-1]','[ 0 1 1]','[-1 0-1]','[ 1 0-1]','[-1 0 1]','[ 1 0 1]'/)
        case(8)
          dom_ind = (/'[-1-1-1]','[ 1-1-1]','[-1 1-1]','[ 1 1-1]','[-1-1 1]','[ 1-1 1]','[-1 1 1]','[ 1 1 1]'/)
      end select
      
C **** choose displayed variable and range
      plot_loop: do      
        scale = 1
                
C         write(*,*) 'Display: 1 displacement domains, n_dom(6[100], 12[110], 8[111]) '
C         write(*,*) '         2 displacement magnitude, scale '
C         write(*,*) '         3 displacement out-of-plane, scale '
C         write(*,*) '         4 in-plane displacement vectors, scale (~50)'
C         write(*,*) '         5 polarisation domains, n_dom(6[100], 12[110], 8[111]) '
C         write(*,*) '         6 polarisation magnitude, scale '
C         write(*,*) '         7 polarisation out-of-plane, scale '
C         write(*,*) '         8 in-plane polarisation vectors, scale (~50)'
C         write(*,*) '         0 exit (0 0)'

        write(*,*) 'Display: 1 displacement in-plane (vector), scale (~20) '
        write(*,*) '         2 displacement out-of-plane (value), scale (~5) '
        write(*,*) '         3 velocity in-plane (vector), scale (~1) '
        write(*,*) '         4 velocity out-of-plane (value), scale (~1)'
        write(*,*) '         5 polarisation in-plane (vector), scale (~5)  '
        write(*,*) '         6 polarisation out-of-plane (value), scale (~1) '
        write(*,*) '         0 exit (0 0)'
        
        if(j_verb==1) then
          write(*,*)
          write(*,*) '         10 displacement domains, 1 '
          write(*,*) '         11 atom mass, .01 '          
          write(*,*) '         12 atom charge, .01 '          
          write(*,*) '         13 displacement magnitude, scale (~20) '
          write(*,*) '         14 displacement component, scale (~20) '
          write(*,*) '         15 velocity magnitude, scale (~1) '
          write(*,*) '         16 velocity component, scale (~1) '
          write(*,*) '         17 polarisation magnitude, scale(~5)  '
          write(*,*) '         18 polarisation component, scale (~5) '
          write(*,*) '         19 polarisation domains, 1 '          
        endif

        fmin = 0.
        read(*,*) mode,scale                              
        if(mode==0) exit plot_loop

        j_cycle = 1
        j_auto = 0     !start by cycling layers and advancing manually to set the right scale etc.

C *** reset masks          
        mask = 1

C *** define plot geometry
        if (mode==14.or.mode==16.or.mode==18) then
          write(*,*) 'Display plane ((0=general, 1=(hk0), 2=(hhl)), component index [1-3]'
          read(*,*) j_plane,ind_c
        else
          write(*,*) 'Display plane ((0=general, 1=(hk0), 2=(hhl)):'
          read(*,*) j_plane
        endif

        if(j_plane==1)then
          e1 = (/1,0,0/)
          e2 = (/0,1,0/)
        elseif(j_plane==2)then
          e1 = (/1,1,0/)
          e2 = (/0,0,1/)
        else						
          do
            write(*,*) 'Input perpendicular vectors (integer) to define the Q-plane e1(3),e2(3):'
            read(*,*) e1,e2
            if(dot_product(e1,e1).ne.0..and.dot_product(e2,e2).ne.0..and.dot_product(e1,e2)==0.) then
              exit
            else
              cycle
            endif
          enddo
        endif

        ev = (/e1(2)*e2(3)-e1(3)*e2(2),e1(3)*e2(1)-e1(1)*e2(3),e1(1)*e2(2)-e1(2)*e2(1)/)
        e1_norm = e1/sqrt(dot_product(1.*e1,1.*e1))
        e2_norm = e2/sqrt(dot_product(1.*e2,1.*e2))
        ev_norm = ev/sqrt(dot_product(1.*ev,1.*ev))
        
        ii = 0
        jj = 100
        do i=1,3
          if(abs(ev(i))==0) cycle
          if(abs(ev(i))<jj) then
            jj = ev(i)
            ii = i
          endif
        enddo
        
C         write(*,*) 'ev,ii,jj',ev,ii,jj
        
        e_slice = 0
        e_slice(ii) = sign(1,jj)
        n_slice = n_row(ii)           !number of horizontal slices corresponding to EV

C     define n_x,n_y according to geometry
        jj = maxloc(e1,1)
        n_x = n_row(jj)
        jj = maxloc(e2,1)
        n_y = n_row(jj)
          
C         write(*,*) 'n_x,n_y',n_x,n_y
C         write(*,*) 'e1,e2,ev',e1,e2,ev
C         write(*,*) 'e_slice',e_slice
        
        allocate(displ_plot(2,n_x,n_y),displ_vect(2,n_x,n_y),i_dom_out(n_x,n_y),ind(3,n_x,n_y))
        

        atom_loop: do
          if(mode<=4.or.(mode>=10.and.mode<17)) then
            if(n_dom/=1) then
              write(*,*) 'Atom numbers: display & domain reference (0 = NONE, -1 = POLARISATION, 99=END)'
              read(*,*) jat,j_atom
            else
              write(*,*) 'Atom number to display (99=END)'
              read(*,*) jat
              j_atom = 0
            endif
            if(jat==99.or.j_atom==99) exit atom_loop
            if(jat<1.or.jat>n_atom.or.j_atom<-1.or.j_atom>n_atom) then
              write(*,*) 'wrong atom number(s), retype ...'
              cycle atom_loop
            endif
            at_name = at_name_par(jat)
          else
            write(*,*) 'Atom number for domain reference (0=NONE, -1=POLARISATION, 99=END)'
            read(*,*) j_atom
            if(j_atom==99) exit atom_loop
            if(j_atom<-1.or.j_atom>n_atom) then
              write(*,*) 'wrong atom number(s), retype ...'
              cycle atom_loop
            endif
            at_name = 'polar'
            jat = 1
          endif

C **** collect map data, start from the beginning
          j_frame = 0
          j_auto = 0
          j_slice = 1      ! we shall be plotting the h0l and hhl planes for consistency, hence cycling over j_row=y=k
          jt = jt0 
          j_shift = 1
        
          x1 = 1.          ! plot frame
          x2 = n_x
          y1 = 1.
          y2 = n_y

          slice_loop: do    !cycle over t-snapshots or supercell layers          
            k = j_slice          

C *** generate index table and domain reference for the actual slice
            do i=1,n_x         
              do j=1,n_y
                ind(:,i,j) = i*e1+j*e2+k*e_slice 
                do ii=1,3
                  ind(ii,i,j) = mod(ind(ii,i,j)-1,n_row(ii))+1
                  if(ind(ii,i,j)<=0) ind(ii,i,j) = ind(ii,i,j)+n_row(ii)
                enddo
                if(j_atom>0) then      
                  i_dom_out(i,j) = i_dom(ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt)
                elseif(j_atom==0) then
                  i_dom_out(i,j) = 1
                else
                  i_dom_out(i,j) = i_dom_p(ind(1,i,j),ind(2,i,j),ind(3,i,j),jt)
                endif
              enddo
            enddo

C ***         define displ_plot(1,n_x,n_y) according to mode
            select case(mode)             !scalar plots
              case(1)
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = dot_product(displ_field(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt),e1_norm)
                    displ_plot(2,i,j) = dot_product(displ_field(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt),e2_norm)
                  enddo
                enddo
              case(2)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = dot_product(displ_field(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt),ev_norm)
                  enddo
                enddo
              case(3)
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = dot_product(vel_field(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt),e1_norm)
                    displ_plot(2,i,j) = dot_product(vel_field(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt),e2_norm)
                  enddo
                enddo
              case(4)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = dot_product(vel_field(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt),ev_norm)
                  enddo
                enddo
              case(5)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = dot_product(polar(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jt),e1_norm)
                    displ_plot(2,i,j) = dot_product(polar(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jt),e2_norm)
                  enddo
                enddo
              case(6)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = dot_product(polar(1:3,ind(1,i,j),ind(2,i,j),ind(3,i,j),jt),ev_norm)
                  enddo
                enddo
              case(10)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = i_dom(ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt)
                  enddo
                enddo
              case(11)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = at_vel_file(4,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat)   !take masses from the last input frame
                  enddo
                enddo
              case(12)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = at_pos_file(4,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat)   !take charges from the last input frame
                  enddo
                enddo
              case(13)                
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = displ_norm(ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt)
                  enddo
                enddo
              case(14)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = displ_field(ind_c,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt)
                  enddo
                enddo
              case(15)                
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = vel_norm(ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt)
                  enddo
                enddo
              case(16)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = vel_field(ind_c,ind(1,i,j),ind(2,i,j),ind(3,i,j),jat,jt)
                  enddo
                enddo
              case(17)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = pol_norm(ind(1,i,j),ind(2,i,j),ind(3,i,j),jt)
                  enddo
                enddo
              case(18)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = polar(ind_c,ind(1,i,j),ind(2,i,j),ind(3,i,j),jt)
                  enddo
                enddo
              case(19)         
                do i=1,n_x         
                  do j=1,n_y
                    displ_plot(1,i,j) = i_dom_p(ind(1,i,j),ind(2,i,j),ind(3,i,j),jt)
                  enddo
                enddo
            end select



C **** open the PGPLOT window
          IF (PGBEG(0,'/xserv',1,1) .LE. 0) STOP
          CALL PGASK(.FALSE.)     ! would not ask for <RET>
          CALL PGSCRN(0, 'white', IER)  !sets the color index of background to WHITE
          CALL PGSCRN(1, 'black', IER)

C ***  initialize PGPLOT map 

          CALL PGPAP(p_size,1.)
          
          do i =1,3
            write(c_e1(i),*) e1(i)
            write(c_e2(i),*) e2(i)
          enddo

          c_x = 'X ['//trim(adjustl(c_e1(1)))//' '//trim(adjustl(c_e1(2)))//' '//trim(adjustl(c_e1(3)))//']'
          c_y = 'Y ['//trim(adjustl(c_e2(1)))//' '//trim(adjustl(c_e2(2)))//' '//trim(adjustl(c_e2(3)))//']'

          if(nfile_min<=9999) then
            write(file_dat,'(a,"_n",i4.4,".dat")') trim(file_master),jt
          elseif(nfile_min>=10000) then
            write(string,'(i8)') jt
            file_dat = trim(file_master)//'_n'//trim(adjustl(string))//'.dat'
          endif

          write(plot_title,104) trim(file_dat),trim(at_name),jt,j_slice,mode
104       format(a,'  ',a,'  frame = ',i6,'  layer = ',i2,'  mode = ',i2)      
          CALL PGSCH(.7)
          CALL PGENV(x1-.5,x2-.5,y1+.5,y2+.5,0,1) !draw the axes
          CALL PGSTBG (0)     !puts opaque bgr to text (erase previous one)
          CALL PGLAB(c_x, c_y,plot_title)  !put the axis labels
          
C         BRIGHT = 0.5
C         CONTRA  = 1.0
C         CALL PALETT(2, CONTRA, BRIGHT)

          CALL PGSHLS (20,.0,.3,.0)     !dark grey  !set my colors
          CALL PGSHLS (21,.0,.4,.7)     !my blue
          CALL PGSHLS (22,120.,.5,1.)   !my red
          CALL PGSHLS (23,240.,.35,.8)  !my green
          CALL PGSHLS (24,60.,.4,.9)    !my violet
          CALL PGSHLS (25,170.,.5,.9)   !my yellow
          CALL PGSHLS (26,320.,.4,.9)   !my turquoise
          CALL PGSHLS (27,.0,.7,.0)     !light grey
          CALL PGSHLS (28,30.,.5,1.)    !my other
          CALL PGSHLS (29,150.,.5,1.)   !my other
          CALL PGSHLS (30,270.,.5,1.)   !my other
          CALL PGSHLS (31,300.,.5,1.0)  !my other

C *** write the domain legend
            CALL PGSLW (5)
            CALL PGSCH(.4)
            do k=1,n_dom
              if(mask(k)==0) cycle
              CALL PGSCI(19+k)
              CALL PGMTXT ( 'RV',.5,1.-.02*k, .0,trim(dom_ind(k)))
C                  PGMTXT (SIDE, DISP, COORD, FJUST, TEXT)
            enddo
            
C *** plot the scalar fields
          if(mode/=1.and.mode/=3.and.mode/=5) then
            displ_plot = displ_plot*scale   ! for vectors the SCALE is embedded in PGVECT

            do i=1,n_x         
              do j=1,n_y
                if(mask(i_dom_out(i,j))==0) cycle
                CALL PGSCI(19+i_dom_out(i,j))
                if(displ_plot(1,i,j)>=.0)then
                  CALL PGSFS (1)            !full circles
                else
                  CALL PGSFS (2)            !hollow circles
                endif              
                CALL PGCIRC (real(i),real(j),sqrt(abs(displ_plot(1,i,j))))
              enddo
            enddo

C *** plot the vector fields
          else
            BLANK = .0    ! blanking
            NC = 0        !arrows centred
            CALL PGSCH(.4)

            do j=1,n_dom
              if(mask(j)==0)cycle
              displ_vect = .0
              where(i_dom_out(:,:)==j)
                displ_vect(1,:,:) = displ_plot(1,:,:)
                displ_vect(2,:,:) = displ_plot(2,:,:)
              end where
              CALL PGSCI(19+j)
              CALL PGVECT(displ_vect(1,:,:),displ_vect(2,:,:),n_x,n_y,1,n_x,1,n_y,scale,nc,TR,blank)              
            enddo
          endif
        call PGCLOS

        if(j_auto.eq.0) then
          write(*,*) 'Increment (OPTIONS = 0, END = 99): [1]'
          read(*,*) j_shift
          if(j_shift.eq.99) exit slice_loop

          if(j_shift.eq.0) then
            options_loop: do
              write(*,*) 'Options:' 
              if(j_auto==0) write(*,*) '   1   toggle MAN to AUTO advance'          !j_auto
              if(j_auto==1) write(*,*) '   1   toggle AUTO to MAN advance'          !j_auto
              if(jt_max>1.and.j_frame==0)write(*,*) '   2   toggle SLICE to FRAME advance' !j_frame
              if(jt_max>1.and.j_frame==1)write(*,*) '   2   toggle FRAME to SLICE advance' !j_frame
              write(*,"('    3   ZOOM (actual frame:',4f6.1,')')") x1,y1,x2,y2
              write(*,*) '   4   adjust scale (actual',scale,')'
              write(*,"('    5   mask domains (actual :',12i2,')')",advance='no') mask
                                                               write(*,"(')')")
              write(*,*) '   6   make a .PS copy'
              write(*,*) '   0   EXIT'
              read(*,*) j_op

              select case (j_op)
                case(1)
                  j_auto = j_auto+1
                  j_auto = mod(j_auto,2)
                  if(j_auto==1) then
                    write(*,*) '       increment & time delay (≥1 sec): '
                    read(*,*) j_shift,j_adv
                    i_shift = 0
                  endif

                case(2)
                  j_frame = j_frame+1
                  j_frame = mod(j_frame,2)
                case(3)
                  write(*,*) '       corner indices (bottom left & top right, confirm/re-type):'
C                 write(*,'(5x,4f6.1)') x1,y1,x2,y2
                  read(*,*) x1,y1,x2,y2
C                   x1 = x1-.5
C                   y1 = y1-.5
C                   x2 = x2+.5
C                   y2 = y2+.5
                case(4)
                  write(*,*) '         new scale factor (-1 invert sign)'
                  read(*,*) res2
                  if(res2==-1) then
                    scale = -scale
                  else
                    scale = res2
                  endif
                  exit options_loop
                case(5)
                  write(*,"('        confirm or retype masks: ')",advance='no')
                  read(*,*) mask
                case(6)
                  j_ps = 1
                  exit options_loop
                case(0)
                  j_shift = 1
                  exit options_loop
              end select
            enddo options_loop
          endif
        else
          call sleep(j_adv)
        endif
          
CC ***  save a .PS copy 

        if(j_ps.eq.1) then  
          if(jt<=9999) then
            write(c_jt,'(i4.4)') jt
          elseif(jt>=10000) then
            write(c_jt,'(i8)') jt
          endif
          c_jt = '_'//adjustl(c_jt)      

          write(c_mode,'("_",i2.2)') mode
          if(j_slice<=99) then
            write(c_slice,'(i2.2)') j_slice
          elseif(j_slice>=100) then
            write(c_slice,'(i8)') j_slice
          endif
          c_slice = '_'//adjustl(c_slice)      

					jfile = 0
					do						!look for existing .txt files to continue numbering
            write(c_jfile,'("_",i2.2)') jfile
            if(jfile==0) c_jfile=''             !don't write file count, if only a single copy

            if(jt==0)then
              file_ps  = trim(file_master)//'_'//at_name(1:3)//trim(c_slice)//trim(c_mode)//trim(c_jfile)//'_dp.ps'
            else			      
              file_ps  = trim(file_master)//trim(c_jt)//'_'//at_name(1:3)//trim(c_slice)//trim(c_mode)//trim(c_jfile)//'_dp.ps'
            endif
            
						inquire(file=file_ps,exist=found_ps)
						if(.not.found_ps) exit				

						jfile = jfile+1
						if(jfile==100) then
							write(*,*)'Tidy up .txt/.ps files to restart count from 01 and type [RET]'
							read(*,*)
							jfile = 1
						endif							
					enddo

          j_ps = PGOPEN(file_ps//'/VCPS')
          if(j_ps.LE.0) then
            write(*,*) 'The .PS file could not be opened: check your PGPLOT installation (drivers)!'
            cycle slice_loop
          endif
					write(*,*) 'Saving PS file: ',file_ps

          CALL PGPAP(8.0,1.0)     ! define the plot area
          CALL PGSLW (2)
          CALL PGSCH(0.8)
          CALL PGENV(x1-.5,x2-.5,y1+.5,y2+.5,0,1) !draw the axes
          CALL PGSTBG (0)     !puts opaque bgr to text (erase previous one)
          CALL PGLAB(c_x, c_y,plot_title)  !put the axis labels


          CALL PGSHLS (20,.0,.3,.0)     !dark grey  !set my colors
          CALL PGSHLS (21,.0,.4,.7)     !my blue
          CALL PGSHLS (22,120.,.5,1.)   !my red
          CALL PGSHLS (23,240.,.35,.8)  !my green
          CALL PGSHLS (24,60.,.4,.9)    !my violet
          CALL PGSHLS (25,170.,.5,.9)   !my yellow
          CALL PGSHLS (26,320.,.4,.9)   !my turquoise
          CALL PGSHLS (27,.0,.7,.0)     !light grey
          CALL PGSHLS (28,30.,.5,1.)    !my other
          CALL PGSHLS (29,150.,.5,1.)   !my other
          CALL PGSHLS (30,270.,.5,1.)   !my other
          CALL PGSHLS (31,300.,.5,1.0)  !my other


C *** write the domain legend
          CALL PGSLW (2)
          CALL PGSCH(.5)
          do k=1,n_dom
            if(mask(k)==0) cycle
            CALL PGSCI(19+k)
            CALL PGMTXT ( 'RV',.5,1.-.03*k, .0,trim(dom_ind(k)))
C                  PGMTXT (SIDE, DISP, COORD, FJUST, TEXT)
          enddo
            
C *** plot the scalar fields
            if(mode/=1.and.mode/=3.and.mode/=5) then
              displ_plot = displ_plot*scale   ! for vectors the SCALE is embedded in PGVECT

              do i=1,n_x         
                do j=1,n_y
                  if(mask(i_dom_out(i,j))==0) cycle
                  CALL PGSCI(19+i_dom_out(i,j))
                  if(displ_plot(1,i,j)>=.0)then
                    CALL PGSFS (1)            !full circles
                  else
                    CALL PGSFS (2)            !hollow circles
                  endif              
                  CALL PGCIRC (real(i),real(j),sqrt(abs(displ_plot(1,i,j))))
                enddo
              enddo

C *** plot the vector fields
            else
              BLANK = .0    ! blanking
              NC = 0        !arrows centred
              CALL PGSCH(.4)

              do j=1,n_dom
                if(mask(j)==0)cycle
                displ_vect = .0
                where(i_dom_out(:,:)==j)
                  displ_vect(1,:,:) = displ_plot(1,:,:)
                  displ_vect(2,:,:) = displ_plot(2,:,:)
                end where
                CALL PGSCI(19+j)
                CALL PGVECT(displ_vect(1,:,:),displ_vect(2,:,:),n_x,n_y,1,n_x,1,n_y,scale,nc,TR,blank)              
              enddo
            endif

            call PGCLOS
            j_ps = 0      !make just one .PS
            cycle slice_loop
          endif     !make .PS (j_ps.eq.1)

C *** stop the movie?
          if(j_auto==1.and.i_shift==n_shift) then !stop/cont automatic show
            write(*,*) 'Continue/stop? (1/0)'
            read(*,*) j_auto
            i_shift = 0
            if(j_auto==0) cycle slice_loop
          endif                


C *** what next?
          if(j_frame==0)then                !cycle layer/snapshot (1/2)
            j_slice=j_slice+j_shift
          else
            jt = jt+j_shift
          endif                                  
          i_shift = i_shift+1

          if(j_slice<1) j_slice = 1
          if(j_slice>n_slice) j_slice = 1

          if(jt<jt0) jt = jt0
          if(jt>jt_max) jt = jt0
          
C             write(*,*) 'i_shift,jt,j_slice',i_shift,jt,j_slice

          enddo slice_loop

          if((mode>4.and.mode<10).or.mode>16) exit atom_loop
        enddo atom_loop

        deallocate(displ_plot,displ_vect,i_dom_out,ind)
      enddo plot_loop
C
C Close the device and exit.
C
888      CALL PGEND
      deallocate(displ_field,displ_norm,i_dom)

      end program mp_dplot55

  
C **** string conversion to all upper case
C     
       subroutine up_case (string)

      character(*), intent(inout)  :: string
      integer                      :: j, nc
      character(len=26), parameter  :: lower = 'abcdefghijklmnopqrstuvwxyz'
      character(len=26), parameter  :: upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

      do j = 1, len(string)
        nc = index(lower, string(j:j))
        if (nc > 0) string(j:j) = upper(nc:nc)
      end do

      end subroutine up_case       


      SUBROUTINE PALETT(TYPE, CONTRA, BRIGHT)
C-----------------------------------------------------------------------
C Set the RAINBOW palette of colors to be used by PGIMAG.
C-----------------------------------------------------------------------
      INTEGER TYPE
      REAL CONTRA, BRIGHT
C
      REAL GL(2), GR(2), GG(2), GB(2)
      REAL RL(9), RR(9), RG(9), RB(9)
      REAL JKL(9), JKR(9), JKG(9), JKB(9)
      REAL HL(5), HR(5), HG(5), HB(5)
      REAL WL(10), WR(10), WG(10), WB(10)
      REAL AL(20), AR(20), AG(20), AB(20)
C
      DATA GL /0.0, 1.0/
      DATA GR /0.0, 1.0/
      DATA GG /0.0, 1.0/
      DATA GB /0.0, 1.0/
C
      DATA RL /-0.5, 0.0, 0.17, 0.33, 0.50, 0.67, 0.83, 1.0, 1.7/
      DATA RR / 0.0, 0.0,  0.0,  0.0,  0.6,  1.0,  1.0, 1.0, 1.0/
      DATA RG / 0.0, 0.0,  0.0,  1.0,  1.0,  1.0,  0.6, 0.0, 1.0/
      DATA RB / 0.0, 0.3,  0.8,  1.0,  0.3,  0.0,  0.0, 0.0, 1.0/
C
      DATA JKL / 0,   0.1,  0.2,  0.33, 0.50, 0.67, 0.83, 1.0, 1.7/
      DATA JKR / 1.0, 0.5,  0.1,  0.1,  0.3,  1.0,  1.0, 1.0, 1.0/
      DATA JKG / 1.0, 0.7,  0.4,   .8,  1.,   1.0,  0.6, 0.0, 1.0/
      DATA JKB / 1.0, 1.0,  0.9,   .6,  0.3,  0.0,  0.0, 0.0, 1.0/
C
      DATA HL /0.0, 0.2, 0.4, 0.6, 1.0/
      DATA HR /0.0, 0.5, 1.0, 1.0, 1.0/
      DATA HG /0.0, 0.0, 0.5, 1.0, 1.0/
      DATA HB /0.0, 0.0, 0.0, 0.3, 1.0/
C
      DATA WL /0.0, 0.5, 0.5, 0.7, 0.7, 0.85, 0.85, 0.95, 0.95, 1.0/
      DATA WR /0.0, 1.0, 0.0, 0.0, 0.3,  0.8,  0.3,  1.0,  1.0, 1.0/
      DATA WG /0.0, 0.5, 0.4, 1.0, 0.0,  0.0,  0.2,  0.7,  1.0, 1.0/
      DATA WB /0.0, 0.0, 0.0, 0.0, 0.4,  1.0,  0.0,  0.0, 0.95, 1.0/
C
      DATA AL /0.0, 0.1, 0.1, 0.2, 0.2, 0.3, 0.3, 0.4, 0.4, 0.5,
     :         0.5, 0.6, 0.6, 0.7, 0.7, 0.8, 0.8, 0.9, 0.9, 1.0/
      DATA AR /0.0, 0.0, 0.3, 0.3, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0,
     :         0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0/
      DATA AG /0.0, 0.0, 0.3, 0.3, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8,
     :         0.6, 0.6, 1.0, 1.0, 1.0, 1.0, 0.8, 0.8, 0.0, 0.0/
      DATA AB /0.0, 0.0, 0.3, 0.3, 0.7, 0.7, 0.7, 0.7, 0.9, 0.9,
     :         0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0/
C
      IF (TYPE.EQ.1) THEN
C        -- gray scale
         CALL PGCTAB(GL, GR, GG, GB, 2, CONTRA, BRIGHT)
      ELSE IF (TYPE.EQ.2) THEN
C        -- rainbow
         CALL PGCTAB(RL, RR, RG, RB, 9, CONTRA, BRIGHT)
      ELSE IF (TYPE.EQ.3) THEN
C        -- heat
         CALL PGCTAB(HL, HR, HG, HB, 5, CONTRA, BRIGHT)
      ELSE IF (TYPE.EQ.4) THEN
C        -- weird IRAF
         CALL PGCTAB(WL, WR, WG, WB, 10, CONTRA, BRIGHT)
      ELSE IF (TYPE.EQ.5) THEN
C        -- AIPS
         CALL PGCTAB(AL, AR, AG, AB, 20, CONTRA, BRIGHT)
      ELSE IF (TYPE.EQ.6) THEN
C        -- JK rainbow
         CALL PGCTAB(JKL, JKR, JKG, JKB, 9, CONTRA, BRIGHT)
      END IF
      END
      
   
  
     
