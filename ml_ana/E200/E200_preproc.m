%% E200_preproc
%  Function to preprocess data in a generic way.
%
%  Order of operations:
%  1. get analysis ROIs
%  2. get energy axis
%      get dE vector
%      apply ROI
%      reorient
%  3. get vignetting correction
%  4. get camera calibration
%  5. loop over shots
%     a. get raw image and bkg
%     b. subtract bkg
%     c. apply vignetting correction
%     d. apply analysis ROI
%     e. reorient
%     f. filter
%     g. remove noise floor / apply thresh.
%     h. apply camera calibration
%     i. make x-y projections
%     j. make energy projection
%     k. plot image
%     l. plot energy projection
%
%  inputs-->
%  data      : struct; main data struct from E200_load_data
%  cam_name  : string; name of camera
%  readwrite : string;
%              'read'  - only read from disk, create from scratch
%                        if not on disk, but don't write to disk
%              'write' - read from disk if there, create from
%                        scratch and save to disk if not
%              'overwrite' - create from scratch and save to disk,
%                        saving over previous value if there
%
% M.Litos 11/4/2013
function [ data ] = E200_preproc( data, cam_name, readwrite )

% option to make plots
plots_on = false;
nfig=0; % initialize figure counter

% default: don't save to remote disk
if nargin<2
    readwrite='read';
end

%% define camera images struct
CAMERA = data.raw.images.(cam_name);

%% get analysis ROIs (if available)
disp('get analysis ROIs');
[data, CAMERA_ana_roi_x, CAMERA_ana_roi_y] = E200_get_ana_roi(data,cam_name,'read');

%% get energy axis (if applicable)
disp('get energy axis');
[data, CAMERA_E_GeV, CAMERA_dE_GeV] = E200_get_Ecal(data,cam_name,'read');

% apply ROI to energy axis
CAMERA_E_roi   = CAMERA_E_GeV (CAMERA_ana_roi_x(1):CAMERA_ana_roi_x(2));
CAMERA_dE_roi  = CAMERA_dE_GeV(CAMERA_ana_roi_x(1):CAMERA_ana_roi_x(2));

% reorient energy axis
% need a way of checking correct orientation is applied to energy axis
if ~strcmpi(cam_name,'CMOS')
    CAMERA_E_GeV  = fliplr(CAMERA_E_GeV);
    CAMERA_dE_GeV = fliplr(CAMERA_dE_GeV);
    CAMERA_E_roi  = fliplr(CAMERA_E_roi);
    CAMERA_dE_roi = fliplr(CAMERA_dE_roi);
end

%% get vignetting correction (if applicable)
disp('get vignetting correction');
[data, CAMERA_vig_corr] = E200_get_vig_corr(data,cam_name,'read');
    
%% get camera calibration
disp('get camera pixel resolution');
um2mm=1E-3;
CAMERA_cal = CAMERA.RESOLUTION(1)*um2mm;

%% get charge per pixel count calibration (if available)
disp('get charge per pixel count');
[data, CAMERA_cnt2e, CAMERA_cnt2nC] = E200_get_Qcal(data,cam_name,'read');

%% loop over shots
disp('loop over shots...');
nshot = length(CAMERA.UID);
for ishot=1:nshot

    %% check if preprocessed values already exist in the data struct
    CAMERA_preprocessed(ishot) = false;
    if isfield(data.processed.vectors,cam_name)
        if isfield(data.processed.vectors.(cam_name).preproc,'preprocessed')
            if length(data.processed.vectors.(cam_name).preproc.preprocessed.dat)>=ishot
                if (data.processed.vectors.(cam_name).preproc.preprocessed.dat(ishot))
                    CAMERA_preprocessed(ishot)=true;
                end
            end    
        end
    end
    
    % preprocess the data
    if ~(CAMERA_preprocessed(ishot)) || strcmpi(readwrite,'overwrite')
        
        % get UID for each shot
        uid = CAMERA.UID(ishot);
        disp(' - - - - - -');
        disp([sprintf(' shot number :%d',ishot)]);
        disp([sprintf(' UID number  :%d',uid)]);
        
        % order of operations in processing
        CAMERA_order = 'bkg, vig, roi, orient, filter, noise';
        
        %% determine if laser was on or off <-- Make into a function
        if (mod(ishot,2)~=0) % odd shots: laser-on
            CAMERA_laser_on   = true;
        else
            CAMERA_laser_on   = false;
        end
        
        % correct for CMOS
        if strcmpi(cam_name,'CMOS')
            CAMERA_laser_on = ~CAMERA_laser_on;
        end
        
        %% get raw images
        disp(' get raw image');
        % load one image from each camera
        [CAMERA_img,CAMERA_bkg]=E200_load_images(CAMERA,uid);
        % convert cell arrays
        CAMERA_img = double(cell2mat(CAMERA_img));
        CAMERA_bkg = double(cell2mat(CAMERA_bkg));
        
        %% subtract backgrounds
        disp(' subtract background');
        if ~strcmpi(cam_name,'CMOS')
            CAMERA_img = CAMERA_img-CAMERA_bkg;
        end
        
        %% apply vignetting correction
        disp(' apply vignetting correction');
        CAMERA_img = CAMERA_vig_corr.*CAMERA_img;
        
        %% apply analysis ROIs
        disp(' apply analysis ROIs');
        CAMERA_img = CAMERA_img(CAMERA_ana_roi_y(1):CAMERA_ana_roi_y(2), ...
            CAMERA_ana_roi_x(1):CAMERA_ana_roi_x(2));
        
        %% reorient image <-- Make into function
        disp(' reorient image');
        if strcmpi(cam_name,'CEGAIN') || strcmpi(cam_name,'CELOSS')
            CAMERA_ana_orient = 'rot90(transpose,2)';
            CAMERA_img = rot90(CAMERA_img',2);
        elseif strcmpi(cam_name,'CMOS')
            %         CAMERA_orient = 'flipud(transpose)';
            %         CAMERA_img = flipud(CAMERA_img');
            CAMERA_ana_orient = 'rot90(img,1)';
            CAMERA_img = rot90(CAMERA_img,1);
        else
            CAMERA_ana_orient = 'natural';
        end
        
        %% filter X-rays <-- Make into function
        disp(' filter X-rays');
        if strcmpi(cam_name,'CEGAIN') || strcmpi(cam_name,'CELOSS')
            CAMERA_medfilt_size = [3,3];
        elseif strcmpi(cam_name,'CMOS')
            CAMERA_medfilt_size = [6,6];
        else
            CAMERA_medfilt_size = [3,3];
        end
        CAMERA_img = medfilt2(CAMERA_img,CAMERA_medfilt_size);
        
        %% subtract noise floor / apply threshold <-- Make into function
        disp(' reduce noise');
        if strcmpi(cam_name,'CEGAIN') % apply threshold
            CAMERA_noise_samp = [451,size(CAMERA_img,1),1,50];
            CAMERA_floor= mean(max(CAMERA_img(451:end,1:50)));
            CAMERA_img  = CAMERA_img.*(CAMERA_img>CAMERA_floor);
        elseif strcmpi(cam_name,'CELOSS') % apply threshold
            CAMERA_noise_samp = [701,size(CAMERA_img,1),1,100];
            CAMERA_floor= mean(max(CAMERA_img(701:end,1:100)));
            CAMERA_img  = CAMERA_img.*(CAMERA_img>CAMERA_floor);
        elseif strcmpi(cam_name,'CMOS') % subtract floor
            CAMERA_noise_samp = [1201,size(CAMERA_img,1),1,200];
            CAMERA_floor= mean(mean(CAMERA_img(1201:end,1:200)));
            CAMERA_img  = CAMERA_img-CAMERA_floor;
            CAMERA_img  = CAMERA_img.*(CAMERA_img>0);
        else
            CAMERA_noise_samp = [1 1 1 1];
        end
        
        %% apply camera calibration
        CAMERA_x   = CAMERA_cal*[0 size(CAMERA_img,2)-1];
        CAMERA_y   = CAMERA_cal*[0 size(CAMERA_img,1)-1];
        
        CAMERA_dx  = abs(CAMERA_x(2)-CAMERA_x(1));
        CAMERA_dy  = abs(CAMERA_y(2)-CAMERA_y(1));
        
        %% make projections
        disp(' make projections');
        % projections in counts per pixel
        CAMERA_proj_x_cnts_px  = sum(CAMERA_img,1) ; % x-projection
        CAMERA_proj_y_cnts_px  = sum(CAMERA_img,2)'; % y-projection

        % projections in counts per mm
        CAMERA_proj_x_cnts_mm  = CAMERA_proj_x_cnts_px/CAMERA_dx; % x-projection
        CAMERA_proj_y_cnts_mm  = CAMERA_proj_y_cnts_px/CAMERA_dy; % y-projection
        
        % projections in nC per mm
        CAMERA_proj_x_nC_mm  = CAMERA_cnt2nC*CAMERA_proj_x_cnts_mm; % x-projection
        CAMERA_proj_y_nC_mm  = CAMERA_cnt2nC*CAMERA_proj_y_cnts_mm; % y-projection

        % projections in counts and nC per GeV
        if strcmpi(cam_name,'CEGAIN') || strcmpi(cam_name,'CELOSS') || ...
                strcmpi(cam_name,'CMOS')
            CAMERA_proj_E_cnts_GeV = CAMERA_proj_y_cnts_px./CAMERA_dE_roi; % E-projection
            CAMERA_proj_E_nC_GeV = CAMERA_cnt2nC*CAMERA_proj_E_cnts_GeV; % E-projection
        else
            CAMERA_proj_E_cnts_GeV = zeros(1,size(CAMERA_img,2));
            CAMERA_proj_E_nC_GeV = zeros(1,size(CAMERA_img,2));
        end
            
        %% make plots
        if (plots_on)
            
            cmap = custom_cmap();
            nfig=0;
            
            % CAMERA image
%             if (ishot==1); nfig=nfig+1; end;
            figure(1);
            imagesc([CAMERA_x(1) CAMERA_x(end)],[CAMERA_y(1) CAMERA_y(end)],CAMERA_img);
            colormap(cmap.mjet);
            colorbar;
            xlabel('x (mm)');
            ylabel('y (mm)');
            title('CAMERA Image');
            
            % Energy projection
%             if (ishot==1); nfig=nfig+1; end;
            figure(2);
            plot(CAMERA_E_roi,CAMERA_proj_E_nC_GeV);
            xlabel('E (GeV)');
            ylabel('nC / GeV');
            title('Energy Projection');
            
            pause(0.5);
        end
                    
        %% store values in data struct
        disp(' save to data struct');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_order,'order','string', ...
            'String describing order of operations in preprocessing.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_laser_on,'laser_on','bool', ...
            'Boolean value that is true if the laser was on for this shot.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_x,'x_mm','mm','x axis pixel positions in mm.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_x_cnts_px,'x_proj_cnts_px','counts','Projection along x in camera counts per pixel.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_x_cnts_mm,'x_proj_cnts_mm','counts','Projection along x in camera counts per mm.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_x_nC_mm,'x_proj_nC_mm','nC','Projection along x in nC per mm.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_y,'y_mm','mm','y axis pixel positions in mm.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_y_cnts_px,'y_proj_cnts_px','counts','Projection along y in camera counts per pixel.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_y_cnts_mm,'y_proj_cnts_mm','counts','Projection along y in camera counts per mm.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_y_nC_mm,'y_proj_nC_mm','nC','Projection along y in nC per mm.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_E_GeV,'E_GeV','GeV','Energy axis pixel values in GeV.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_dE_GeV,'dE_GeV','GeV','Energy width of each pixel row in GeV.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_E_cnts_GeV,'E_proj_cnts_GeV','counts','Projection along energy axis in camera counts per GeV.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_proj_E_nC_GeV,'E_proj_nC_GeV','nC','Projection along energy axis in nC per GeV.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_vig_corr,'vig_corr','','Vignetting correction factor for each pixel.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_ana_roi_x,'x_ana_roi','px','Analysis ROI pixel limits along x.');
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_ana_roi_y,'y_ana_roi','px','Analysis ROI pixel limits along y.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_ana_orient,'ana_orient','','Analysis orientation of camera.');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_medfilt_size,'medfilt_size','px','Size of median filter area as [x y].');
        
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_noise_samp,'noise_samp','px', ...
            'Pixel range of noise sampling region as [xmin xmax ymin ymax].');
        
        CAMERA_preprocessed(ishot)=true;
        data = E200_add_proc_vector(data,cam_name,'preproc',ishot,uid, ...
            CAMERA_preprocessed(ishot),'preprocessed','bool', ...
            'Boolean value that is true if the data has already been preprocessed.');
        
    end
                        
end%for

%% save processed data to remote disk
if ... % strcmpi(readwrite,'overwrite') || ...
    strcmpi(readwrite,'write') %&& ~(CAMERA_preprocessed))
    E200_save_remote(data);
end

end%function
