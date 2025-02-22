  
      program mp_filter55

C *************************************************************************************
C *****
C ***** %%%%%%%%%%%%%%%%   		  program MP_PDF  1.55   		 %%%%%%%%%%%%%%%%%%%%%%%%%%%%
C *****
C *****   calculates the pair distribution functions (PDF) for simulated supercell data
C *****
C**********					Copyright (C) 2023  Jiri Kulda, Grenoble/Prague          **********
C**	
C** This file is part MP_TOOLS developed and maintained by Jiri Kulda <jkulda@free.fr>
C**
C**	MP_TOOLS are free software: you can use it, redistribute it and/or modify it 
C**	under the terms of the GNU General Public License as published by the Free Software 
C**	Foundation, either version 3 of the License, or (at your option) any later version, 
C**	for details see <https://www.gnu.org/licenses/>
C**
C**	This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
C**	without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  
C**	See the GNU General Public License for more details.
C**
C ***** %%%%%%%%%%%%%%%%   		  program MP_FILTER  1.55   		 %%%%%%%%%%%%%%%%%%%%%%%%%%%%
C *****

C ***** Ver. 1.50	- start of new series (identical to mp_pdf 1.42) as MP_PDF
C ***** 
C ***** Ver. 1.51	- all data arrays allocatable, no predefined array size limits
C ***** 					- supercell format in .PAR
C *****						- number of correlation pairs read from .PAR (don't use ver. 1.50!)
C *****
C ***** Ver 1.53  - record length 4096, all data 32bit length
C *****						- at_mass is saved as at_veloc(4,j,k)
C *****						- at_charge is saved as at_pos(4,j,k)
C *****           - CELL and QUICK data type (BULK not eligible for PDF)
C *****						- secondary sampling volume clipped for highly anisotropic or 2D supercells
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
C *****						1 going for the header record
C *****
C ***** atom positions are converted from reduced lattice coordinates (x) to real space distances
C ***** 
  
CC  		use omp_lib
  		
      integer,parameter :: l_rec  =  1024		    !record length in real(4)
      real,parameter    :: pi = 3.14159

			real,allocatable ::  w(:)
      
      character(4)   :: c_int(2),c_fil(2),version,head,atom
      character(10)  :: pg_out,section,c_date,c_time,c_zone,c_nfile_min,c_nfile,c_jfile
      character(16)  :: sim_type_par,data_type,string16,f_name,filter_name,f_short,f_short2
      character(40)  :: subst_name,file_master,file_master_out,time_stamp,int_mode,string
      character(60)  :: file_dat_in,file_dat_out,file_dat_t0,file_log,line
      character(128) :: cwd_path,plot_header
      character(l_rec):: header_record
      character(l_rec),allocatable:: header(:)
      
			logical ::  nml_in,found_txt,found_ps,t_single

C     integer ::  j_proc,proc_num,proc_num_in,thread_num,thread_num_max,m,j_name,jm,j1m,j2m,j_mode
      integer ::  nfile_step,j_head_in,j_verb,n_tot,n_head,i_time(8),n_filter,n_filter2,j_filter
      integer ::  i,j,k,ii,j0,jj,ind,ind2,jat,i_rec,ind_rec,nrec,ncell,nrow,nlayer,nsuper,nfile,nfile_t0,nfile_min,nfile_max
      integer ::  i_sample,n_sample,n_sample2,i_save,ifile,jfile,ifile0,ier,ios
      
      real :: tt0,tt,sc_r,f_fwhm,filter_fwhm

C **** the following variables MUST have the following type(4) or multiples because of alignement in the binary output file
      character(4),allocatable :: at_name_out(:)
      integer(4),allocatable   :: at_ind_in(:),nsuper_r(:)	

      real(4),allocatable ::	at_pos_in(:),at_pos_out(:,:),at_occup_r(:),at_base(:,:),t_dump_out(:)
      real(4),allocatable ::	at_pos1_in(:),at_pos1_out(:,:)
      real(4),allocatable ::	at_vel_in(:),at_vel_out(:,:)
      real(4),allocatable ::	at_vel1_in(:),at_vel1_out(:,:)

      character(16)  :: sim_type,dat_type,input_method,file_par,dat_source
      integer(4)     :: n_row(3),n_atom,n_eq,j_force,j_shell_out,n_traj,n_cond,n_rec,n_tot_in,idum
      real(4)        :: rec_zero(l_rec),t_ms,t_step,t_step_in,t_dump,t_dump_in,t0,t1,a_par(3),angle(3),a_par_pdf(3),temp

      namelist /data_header_1/sim_type,dat_type,input_method,file_par,subst_name,t_ms,t_step,t_dump,temp,a_par,angle,
     1    n_row,n_atom,n_eq,n_traj,j_shell_out,n_cond,n_rec,n_tot,filter_name,filter_fwhm             !scalars & known dimensions
      namelist /data_header_2/at_name_out,at_base,at_occup_r,at_base,nsuper_r           !allocatables
     
CC      namelist /mp_gen/ j_verb,j_proc       
CC      namelist /mp_out/ j_weight,j_xray,j_logsc,j_txt,j_grid,pg_out       
CC      										!general rule: namelists of tools should only contain their local parameters
CC                          !what is of global interest they should pass into data_header
CC			namelist /mp_pdf/ n_pdf,pdf_step,a_par_pdf,n_h,j_acc,j_smooth,n_corr
CC			

C ********************* Initialization *******************************      

			write(*,*) '*** Program MP_FILTER 1.55 ** Copyright (C) Jiri Kulda (2023) ***'
			write(*,*)
			
C ********************* Get a time stamp and open a .LOG file *******************************
      call getcwd(cwd_path)
	    call date_and_time(c_date,c_time,c_zone,i_time)
	    write(time_stamp,110) c_date(1:4),c_date(5:6),c_date(7:8),c_time(1:2),c_time(3:4),c_time(5:6)
110		format(a,'/',a,'/',a,' ',a,':',a,':',a)	    
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
			write(9,*) trim(time_stamp),'  MP_FILTER 1.55  ',trim(cwd_path)
			write(9,*) 
      
C *** Generate data file access
			write(*,*) 'Input data file_master: '
			read(*,*) file_master 
						
      write(*,*) 'Read data files number min, max: '
      read(*,*)   nfile_min,nfile_max
      nfile_step = 1
			
      nfile = ((nfile_max-nfile_min)/nfile_step)+1
      
      if(nfile_min<=9999) then
        write(file_dat_t0,'("./data/",a,"_n",i4.4,".dat")') trim(file_master),nfile_min
      elseif(nfile_min>=10000) then
        write(string,'(i8)') nfile_min
        file_dat_t0 = './data/'//trim(file_master)//'_n'//trim(adjustl(string))//'.dat'
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
        write(*,*)		'Input data:  ',dat_source,version,n_head
        
        allocate(header(n_head))
        header(i_rec) = header_record

        i_rec = i_rec+1   							
        read(1,rec=i_rec) header_record
        read(header_record,nml=data_header_1)	
        write(header_record,nml=data_header_1)	      !update header record by parameters potentially absent in input data like filter_name,filter_fwhm
        header(i_rec) = header_record
      else
      	write(*,*) 'header record old, wrong or missing'
      	write(*,*) trim(header_record)
      	stop
      endif 
      
      i_rec = i_rec+1   							
      read(1,rec=i_rec) header_record
      header(i_rec) = header_record
C        read(header_record,nml=data_header_2)			
      close(1)
      
      if(trim(input_method)/='CELL') then
        write(*,*) 'WARNING: the input data were not produced by the CELL input method,'
        write(*,*) 'the algorithm as such may work, BUT as there is no guaranteed relationship'
        write(*,*) 'between the data position in the .BIN file and the position of the related ,'
        write(*,*) 'atom in the simulation box, the results when adding several snapshots'
        write(*,*) 'may become COMPLETELY IMPREVISIBLE!'
        write(*,*) 
        write(*,*) 'Do you wish to continue anyways, at YOUR risks & perils? (1/0)'
        read(*,*) jj
        if(jj/=1) stop
      endif

      j_filter = 2
      n_filter2 = 10
      n_sample2 = 2
      
      do
        write(*,*) 'Filter type (1 rectangular, 2 smooth) & FWHM (max NFILE/2 for SMOOTH): [confirm 2, 10]'
        read(*,*) j_filter,n_filter2
        if(j_filter==1.and.n_filter2>nfile) then
          write(*,*) 'Filter FWHM must be <= NFILE, retype all ...'
          cycle
        elseif(j_filter==2.and.2*n_filter2>nfile) then
          write(*,*) 'Filter FWHM value must be <= NFILE/2, retype all ...'
          cycle
        endif
        exit
      enddo
      
      do
        write(*,*) 'Number of samples per filter FWHM [2]'
        read(*,*) n_sample2
        if(mod(n_filter2,n_sample2)==0) exit
        write(*,*) 'Filter length must be divisible by n_sample, retype ...'
      enddo

      n_filter = j_filter*n_filter2         !assuming FWHM = NFILE/2 for SMOOTH filters, otherwise modify previous dialogue & here
      n_sample = j_filter*n_sample2
      t_step_in = t_step
      
      allocate(w(n_filter))
     
      if (j_filter==1) then
        w = 1.
C       f_fwhm = .5*n_filter*t_step_in
C       write(f_short,*)n_filter/2
        f_name = 'Rectangular'
C       f_short = 'r'//trim(adjustl(f_short))//'f'
      elseif(j_filter==2) then
        do i=1,n_filter
          w(i) = 1.-cos(2.*pi*i/real(n_filter))       ! SMOOTH == Hann profile
        enddo
C       f_fwhm = .5*n_filter*t_step_in
        f_name = 'Hann'
C       write(f_short,*)n_filter/2
C       f_short = 'h'//trim(adjustl(f_short))//'f'
      else  
        write(*,*) "Invalid filter option, STOP"
        stop
      endif
      w = w/sum(w)
      f_fwhm = n_filter2*t_step_in      
      write(f_short2,*) n_filter2
      write(f_short,*) n_filter2/n_sample2
      f_short = trim(adjustl(f_short))//f_name(1:1)//trim(adjustl(f_short2))//'f'

      write(*,*) trim(f_name),' filter profile FWHM =',f_fwhm
C     write(*,*) 'w(i)',w
      
C ***  Edit output file name
      string = file_master
      write(*,*) 'Output data file_master (confirm, &append or replace): ', string
      read(*,*) string
      string = adjustl(string)
      if(trim(string)/=file_master.and.string(1:1)=='&') then
        file_master_out = trim(file_master)//trim(string(2:))//'_'//trim(f_short)
      else
        file_master_out = trim(string)//'_'//trim(f_short)
      endif
      
C *** Allocate and clear the histogram arrays for accumulation across several snapshots	       
CC			allocate (at_pos_file(4,nsuper,n_atom),at_ind_file(4,nsuper,n_atom),at_pos_in(4*n_tot),at_ind_in(4*n_tot))
			allocate (at_pos_in(4*n_tot),at_ind_in(4*n_tot),at_pos_out(4*n_tot,n_sample),t_dump_out(n_sample))
			if(n_traj>=1) allocate (at_vel_in(4*n_tot),at_vel_out(4*n_tot,n_sample))
			if(j_shell_out==1) then
			  allocate (at_pos1_in(4*n_tot),at_pos1_out(4*n_tot,n_sample))
			  if(n_traj>=1) allocate (at_vel1_in(4*n_tot),at_vel1_out(4*n_tot,n_sample))
			endif

      call cpu_time(t0)
      at_pos_out = .0
      at_vel_out = .0
      if(j_shell_out==1) then
        at_pos1_out = .0
        if(n_traj>=1) then
          at_vel1_out = .0
        endif
      endif

      i_save = 0     
      file_loop: do ifile=nfile_min,nfile_max
        if(ifile<=9999) then
          write(file_dat_in,'("./data/",a,"_n",i4.4,".dat")') trim(file_master),ifile
        elseif(ifile>=10000) then
          write(string,'(i8)') ifile
          file_dat_in = './data/'//trim(file_master)//'_n'//trim(adjustl(string))//'.dat'
        endif

        jfile = ifile-nfile_min+1

        open(1,file=file_dat_in,status ='old',access='direct',action='read',form='unformatted',recl=4*l_rec,iostat=ios)
        if(ios.ne.0) then
          write(*,*) 'File ',trim(file_dat_in),' not opened! IOS =',ios
          write(*,*) 'Skip(1), stop execution(0)?'
          read(*,*) jj
          if(jj==1) exit file_loop
          if(jj==0) stop
        endif

        do i_rec = 1,n_head
          read(1,rec=i_rec) header(i_rec)
        enddo
        read(header(2),nml=data_header_1)	
        t_dump_in = t_dump

        if(jfile==1) then
          i_rec = n_head	
          do i=1,n_rec-1
            i_rec = i_rec+1
            read(1,rec=i_rec) at_ind_in((i-1)*l_rec+1:i*l_rec)			 
          enddo	
          i_rec = i_rec+1
          read(1,rec=i_rec) at_ind_in((n_rec-1)*l_rec+1:4*n_tot)
        else
          i_rec = n_head+n_rec
        endif			

        do i=1,n_rec-1
          i_rec = i_rec+1
          read(1,rec=i_rec) at_pos_in((i-1)*l_rec+1:i*l_rec)			
        enddo	
        i_rec = i_rec+1
        read(1,rec=i_rec) at_pos_in((n_rec-1)*l_rec+1:4*n_tot)	
 
        if(n_traj>=1) then
          do i=1,n_rec-1
            i_rec = i_rec+1
            read(1,rec=i_rec) at_vel_in((i-1)*l_rec+1:i*l_rec)			
          enddo	
          i_rec = i_rec+1
          read(1,rec=i_rec) at_vel_in((n_rec-1)*l_rec+1:4*n_tot)	
        endif
 
        if(j_shell_out==1) then           ! read SHELL data
          do j=1,n_rec-1
            i_rec = i_rec+1
            read(1,rec=i_rec) at_pos1_in((j-1)*l_rec+1:j*l_rec)      
          enddo  
          i_rec = i_rec+1
          read(1,rec=i_rec) at_pos1_in((n_rec-1)*l_rec+1:4*n_tot)
        
          if(n_traj>=1) then
            do i=1,n_rec-1
              i_rec = i_rec+1
              read(1,rec=i_rec) at_vel1_in((i-1)*l_rec+1:i*l_rec)			
            enddo	
            i_rec = i_rec+1
            read(1,rec=i_rec) at_vel1_in((n_rec-1)*l_rec+1:4*n_tot)	
          endif
        endif        
        close(1)
        
C *** accumulate the samples
        sample_loop: do i_sample = 1,n_sample

          j0 = (i_sample-1)*(n_filter2/n_sample2) !initial sample shift
C         write(*,*) 'ifile,i_sample,j0',ifile,i_sample,j0

          if(jfile>j0) then    
            j = mod(jfile-j0,n_filter)
            if(j==0) j=n_filter
        
            at_pos_out(:,i_sample) = at_pos_out(:,i_sample)+w(j)*at_pos_in
            if(n_traj>=1) at_vel_out(:,i_sample) = at_vel_out(:,i_sample)+w(j)*at_vel_in
            if(j_shell_out==1) at_pos1_out(:,i_sample) = at_pos1_out(:,i_sample)+w(j)*at_pos1_in
            if(j_shell_out==1.and.n_traj>=1) at_vel1_out(:,i_sample) = at_vel1_out(:,i_sample)+w(j)*at_vel1_in
            if(j==n_filter/2) t_dump_out(i_sample) = t_dump_in
C             if(j==n_filter/2) write(*,*) 'i_sample,j0,j,t_dump_out(i_sample)',i_sample,j0,j,t_dump_out(i_sample)
 
            if(j==n_filter) then                     !accumulation finished, write OUTPUT
              i_save = i_save+1
              if(i_save<=9999) then
                write(file_dat_out,'("./data/",a,"_n",i4.4,".dat")') trim(file_master_out),i_save
              elseif(i_save>=10000) then
                write(string,'(i8)') i_save
                file_dat_out = './data/'//trim(file_master_out)//'_n'//trim(adjustl(string))//'.dat'
              endif
              open(2,file=file_dat_out,access='direct',form='unformatted',recl=4*l_rec)
C        write(*,*) 'OUT: ifile,i_sample,j0,j,file_dat_out,t_dump',ifile,i_sample,j0,j,file_dat_out,t_dump_out(i_sample)

              if(i_save==1) then 
                write(*,*) 'Start:    ',file_dat_out
                write(*,*) '                 (working ... may take a short while)'
              endif
              
              if(i_save==10*(i_save/10)) write(*,*)trim(file_dat_out)

C *** write the header record
              if(n_traj>=1) then
                n_traj = 1 
              else
                n_traj = 0 
              endif                         !filtered data have positions and velocities only
              t_dump = t_dump_out(i_sample) !update header t_dump corresponding to w(i) maximum
              t_step = t_step_in*n_filter2/n_sample2  !this is in fact t_step_out ... this is the place!
              filter_fwhm = f_fwhm
              filter_name = f_name
              write(header(2),nml=data_header_1)	!update data_header_1 with t_step,t_dump,filter_name,filter_fwhm

              do i_rec=1,n_head
                write(2,rec=i_rec) header(i_rec)        
              enddo
              i_rec = n_head	
          
C *** do the rest	
              do i=1,n_rec-1
                i_rec = i_rec+1
                write(2,rec=i_rec) at_ind_in((i-1)*l_rec+1:i*l_rec)			
              enddo
              i = n_rec
              i_rec = i_rec+1
              write(2,rec=i_rec)rec_zero										!the last one has to be padded by 0
              write(2,rec=i_rec) at_ind_in((n_rec-1)*l_rec+1:4*n_tot)

              do i=1,n_rec-1
                i_rec = i_rec+1
                write(2,rec=i_rec) at_pos_out((i-1)*l_rec+1:i*l_rec,i_sample)
              enddo
              i = n_rec
              i_rec = i_rec+1
              write(2,rec=i_rec)rec_zero										!the last one has to be padded by 0
              write(2,rec=i_rec) at_pos_out((n_rec-1)*l_rec+1:4*n_tot,i_sample)
              at_pos_out(:,i_sample) = .0

              if(n_traj>=1) then
                do i=1,n_rec-1
                  i_rec = i_rec+1
                  write(2,rec=i_rec) at_vel_out((i-1)*l_rec+1:i*l_rec,i_sample)
                enddo
                i = n_rec
                i_rec = i_rec+1
                write(2,rec=i_rec)rec_zero										!the last one has to be padded by 0
                write(2,rec=i_rec) at_vel_out((n_rec-1)*l_rec+1:4*n_tot,i_sample)
                at_vel_out(:,i_sample) = .0
              endif
  
              if(j_shell_out==1) then
                do i=1,n_rec-1
                  i_rec = i_rec+1
                  write(2,rec=i_rec) at_pos1_out((i-1)*l_rec+1:i*l_rec,i_sample)
                enddo
                i = n_rec
                i_rec = i_rec+1
                write(2,rec=i_rec)rec_zero										!the last one has to be padded by 0
                write(2,rec=i_rec) at_pos1_out((n_rec-1)*l_rec+1:4*n_tot,i_sample)
                at_pos1_out(:,i_sample) = .0

                if(n_traj>=1) then
                  do i=1,n_rec-1
                    i_rec = i_rec+1
                    write(2,rec=i_rec) at_vel1_out((i-1)*l_rec+1:i*l_rec,i_sample)
                  enddo
                  i = n_rec
                  i_rec = i_rec+1
                  write(2,rec=i_rec)rec_zero										!the last one has to be padded by 0
                  write(2,rec=i_rec) at_vel1_out((n_rec-1)*l_rec+1:4*n_tot,i_sample)
                  at_vel1_out(:,i_sample) = .0
                endif
              endif
            endif
          endif
        enddo sample_loop
 
      enddo file_loop	
      
      write(*,*) 'Finished: ',file_dat_out
      write(*,*) 'Total of',i_save,' files written'  
        		            
      end program mp_filter55
   
  
C **********************************************************************************************************
C **** string conversion to all upper case
C     
 			subroutine up_case (string)

			character(*), intent(inout)	:: string
			integer											:: j, nc
			character(len=26), parameter	:: lower = 'abcdefghijklmnopqrstuvwxyz'
			character(len=26), parameter	:: upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

			do j = 1, len(string)
				nc = index(lower, string(j:j))
				if (nc > 0) string(j:j) = upper(nc:nc)
			end do

			end subroutine up_case	     

C **** string conversion to all lower case
C          
 			subroutine down_case (string)

			character(*), intent(inout)	:: string
			integer											:: j, nc
			character(len=26), parameter	:: lower = 'abcdefghijklmnopqrstuvwxyz'
			character(len=26), parameter	:: upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'

			do j = 1, len(string)
				nc = index(upper, string(j:j))
				if (nc > 0) string(j:j) = lower(nc:nc)
			end do

			end subroutine down_case	     
     

     