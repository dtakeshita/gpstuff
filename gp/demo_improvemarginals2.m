%DEMO_IMPROVEMARGINALS  Demonstration of joint marginal posterior improvements 
%                       in Laplace and EP algorithms.
%
%  Description
%    Demonstration of joint marginal posterior corrections of latent
%    variables in Bioassay example. Demonstrated corrections are 'cm2'
%    (Laplace) and 'fact' (EP) with Gaussian copula to obtain a
%    correction for bivariate marginal posterior. The uncorrected and
%    corrected posterior distributions are compared to true posterior
%    evaluated in grid and to MCMC samples.
%
%  See also
%    GP_PREDCM, GP_RND, DEMO_BINOMIAL2
%

% Copyright (c) 2013 Aki Vehtari

% This software is distributed under the GNU General Public 
% License (version 3 or later); please refer to the file 
% License.txt, included with the software, for details.

% Bioassay data from Gelman et al (p. 89, 2004)
x=[-0.86 -0.3 -0.05 .73]';
% number of trials
N=[5 5 5 5]';
% number of successes
y=[0 1 3 5]';
% n
[n, nin] = size(x);

xt1=linspace(-2,4.5,50);
xt2=linspace(-5,25,50);
[XT1,XT2]=meshgrid(xt1,xt2);
xt=[XT1(:) XT2(:)];

% Use plotting code to make a model with fixed prior (as in Gelman et
% al (2004) and a model with prior with hyperparameters
for i1=1:2

  % Create parts of the covariance function
  switch i1
    case 1
      % fixed prior is used to follow Gelman et al (2004)
      fprintf('Binomial model with fixed vague prior\n')
      cfc = gpcf_constant('constSigma2',20^2,'constSigma2_prior',[]);
      cfl = gpcf_linear('coeffSigma2',20^2,'coeffSigma2_prior',[]);
      grids='';
    case 2
      % Half-Student's t-prior is used to give flat prior in the
      % interesting region with respect to the likelihood
      fprintf('Binomial model with prior with hyperparameters\n')
      cfc = gpcf_constant('constSigma2_prior',prior_sqrtt('s2',20^2));
      cfl = gpcf_linear('coeffSigma2_prior',prior_sqrtt('s2',20^2));
      grids='+grid';
  end
  % Create the GP structure
  gp = gp_set('lik', lik_binomial(), 'cf', {cfc cfl}, 'jitterSigma2', 1e-6);

  figure(i1)
  set(gcf,'units','centimeters');
  set(gcf,'pos',[29.9 2 24 18.5]);
  set(gcf,'papertype','a4','paperorientation','landscape',...
          'paperunits','centimeters','paperpositionmode','auto')

  % ------- MCMC approximation --------
  fprintf('MCMC approximation\n')

  gp = gp_set(gp, 'latent_method', 'MCMC', 'jitterSigma2', 1e-4);

  [rgp,g,opt] = gp_mc(gp, x, y, 'z', N, 'nsamples', 500, 'repeat', 4, 'display', 0);
  rgp=thin(rgp,101);

  % Get samples from the joint distribution of the latent values at 0 and 1
  % to compute the corresponding linear model parameters alpha and beta
  % in Gelman et al (2004)
  fprintf('Sampling from the posterior of alpha and beta\n')
  fs = gp_rnd(rgp, x, y, [0 1]', 'z', N, 'zt', [5 5]', 'nsamp', 10000);
  a=fs(1,:);b=fs(2,:)-fs(1,:);
  % compute samples from the LD50 given b>0 (see, Gelman et al (2004))
  ld50s=-a(b>0)./b(b>0);

  rmc.fs=fs;
  rmc.a=a;
  rmc.b=b;
  rmc.ld50s=ld50s;

  fprintf('Plotting\n')
  subplot('Position',[0.050 0.700 0.164 0.250]);
  pmc=lgpdens([a' b'],xt,'range',[-2 3 -1 16],'gridn',40,'speedup','on');
  contour(XT1,XT2,reshape(pmc,50,50),'k');
  xlim([-2.4 4]),ylim([-4 24])
  xlabel('alpha')
  ylabel('beta')
  ax=axis;
  h=line([ax(1), ax(2)], [0 0]);
  set(h, 'Color', 'k');
  h=line([0 0], [ax(3), ax(4)]);
  set(h, 'Color', 'k');
%   hzline
%   vzline
  title('MCMC')
  %h=contour(XT1,XT2,reshape(pmc,50,50),.05*max(pmc),'k--');
  subplot('Position',[0.050 0.380 0.164 0.250]);
  hist(ld50s,-0.6:.04:0.6),set(gca,'xlim',[-.6 .6])
  h=get(gca,'Children');
  % set(h,'FaceColor',color1)
  set(gca,'ytick',[])
  ylim([0 2500])
  xlabel('LD50')
  h1=text(prctile(ld50s,2.5),2200,'2.5%','HorizontalAlignment','center');
  h2=text(prctile(ld50s,50),2350,'50%','HorizontalAlignment','center');
  h3=text(prctile(ld50s,97.5),2200,'97.5%','HorizontalAlignment','center');
  hl=line(repmat(prctile(ld50s,[2.5 50 97.5]),2,1),[0 0 0;2150 2300 2150],'Color','k');
  drawnow
  
  % ------- Laplace approximation --------
  tic
  fprintf('Laplace%s approximation\n',grids)
  gp = gp_set(gp, 'latent_method', 'Laplace');

  % Set the options for the optimization
  opt=optimset('TolFun',1e-3,'TolX',1e-3,'Display','off');
  % Optimize with the scaled conjugate gradient method
  gp=gp_optim(gp,x,y,'z',N,'opt',opt);
  % Form a weighted grid of samples, which is used to integrate over
  % the hyperparameters
  gpia=gp_ia(gp,x,y,'z',N,'int_method','grid');

  fprintf('Sampling from the posterior of alpha and beta\n')
  fs = gp_rnd(gpia, x, y, [0 1]', 'z', N, 'nsamp', 10000);
  a=fs(1,:);b=fs(2,:)-fs(1,:);
  % compute samples from the LD50 given b>0 (see, Gelman et al (2004))
  ld50s=-a(b>0)./b(b>0);

  rla.fs=fs;
  rla.a=a;
  rla.b=b;
  rla.ld50s=ld50s;

  fprintf('Plotting\n')
  subplot('Position',[0.244 0.700 0.164 0.250]);
  pmc=lgpdens([a' b'],xt,'range',[-2 3 -1 16],'gridn',40,'speedup','on');
  contour(XT1,XT2,reshape(pmc,50,50),'k');
  xlim([-2.4 4]),ylim([-4 24])
  xlabel('alpha')
  %ylabel('beta')
  ax=axis;
  h=line([ax(1), ax(2)], [0 0]);
  set(h, 'Color', 'k');
  h=line([0 0], [ax(3), ax(4)]);
  set(h, 'Color', 'k');
%   hzline
%   vzline
  title(sprintf('Laplace%s',grids))
  subplot('Position',[0.244 0.380 0.164 0.250]);
  hist(ld50s,-0.6:.04:0.6),set(gca,'xlim',[-.6 .6])
  h=get(gca,'Children');
  set(gca,'ytick',[])
  ylim([0 2500])
  xlabel('LD50')
  h1=text(prctile(ld50s,2.5),2200,'2.5%','HorizontalAlignment','center');
  h2=text(prctile(ld50s,50),2350,'50%','HorizontalAlignment','center');
  h3=text(prctile(ld50s,97.5),2200,'97.5%','HorizontalAlignment','center');
  hl=line(repmat(prctile(ld50s,[2.5 50 97.5]),2,1),[0 0 0;2150 2300 2150],'Color','k');
  subplot('Position',[0.244 0.060 0.164 0.250]);
  qqplot(rmc.ld50s,ld50s)
  xlim([-.8 1.3])
  ylim([-50 60])
  box on
  drawnow

  fprintf('Laplace+cm2%s approximation\n',grids)
  % Get samples from the joint distribution of the latent values at 0 and 1
  % to compute the corresponding linear model parameters alpha and beta
  % in Gelman et al (2004)
  fprintf('Sampling from the posterior of alpha and beta\n')
  fs = gp_rnd(gpia, x, y, [0 1]', 'z', N, 'nsamp', 10000, 'fcorrections', 'cm2');
  a=fs(1,:);b=fs(2,:)-fs(1,:);
  % compute samples from the LD50 given b>0 (see, Gelman et al (2004))
  ld50s=-a(b>0)./b(b>0);

  rlac.fs=fs;
  rlac.a=a;
  rlac.b=b;
  rlac.ld50s=ld50s;

  fprintf('Plotting\n')
  subplot('Position',[0.438 0.700 0.164 0.250]);
  pmc=lgpdens([a' b'],xt,'range',[-2 3 -1 16],'gridn',40,'speedup','on');
  contour(XT1,XT2,reshape(pmc,50,50),'k');
  xlim([-2.4 4]),ylim([-4 24])
  xlabel('alpha')
  %ylabel('beta')
  ax=axis;
  h=line([ax(1), ax(2)], [0 0]);
  set(h, 'Color', 'k');
  h=line([0 0], [ax(3), ax(4)]);
  set(h, 'Color', 'k');
%   hzline
%   vzline
  title(sprintf('Laplace+cm2%s',grids))
  subplot('Position',[0.438 0.380 0.164 0.250]);
  hist(ld50s,-0.6:.04:0.6),set(gca,'xlim',[-.6 .6])
  h=get(gca,'Children');
  % set(h,'FaceColor',color1)
  set(gca,'ytick',[])
  ylim([0 2500])
  xlabel('LD50')
  h1=text(prctile(ld50s,2.5),2200,'2.5%','HorizontalAlignment','center');
  h2=text(prctile(ld50s,50),2350,'50%','HorizontalAlignment','center');
  h3=text(prctile(ld50s,97.5),2200,'97.5%','HorizontalAlignment','center');
  hl=line(repmat(prctile(ld50s,[2.5 50 97.5]),2,1),[0 0 0;2150 2300 2150],'Color','k');
  subplot('Position',[0.438 0.060 0.164 0.250]);
  qqplot(rmc.ld50s,ld50s)
  xlim([-.8 1.3])
  ylim([-50 60])
  ylabel('')
  box on
  drawnow

  fprintf('EP%s approximation\n',grids)
  gp = gp_set(gp, 'latent_method', 'EP');

  % Set the options for the optimization
  opt=optimset('TolFun',1e-3,'TolX',1e-3,'Display','off');
  % Optimize with the scaled conjugate gradient method
  gp=gp_optim(gp,x,y,'z',N,'opt',opt);
  % Form a weighted grid of samples, which is used to integrate over
  % the hyperparameters
  gpia=gp_ia(gp,x,y,'z',N,'int_method','grid');

  % Get samples from the joint distribution of the latent values at 0 and 1
  % to compute the corresponding linear model parameters alpha and beta
  % in Gelman et al (2004)
  fprintf('Sampling from the posterior of alpha and beta\n')
  fs = gp_rnd(gpia, x, y, [0 1]', 'z', N, 'zt', [5 5]', 'nsamp', 10000);
  a=fs(1,:);b=fs(2,:)-fs(1,:);
  % compute samples from the LD50 given b>0 (see, Gelman et al (2004))
  ld50s=-a(b>0)./b(b>0);

  rep.fs=fs;
  rep.a=a;
  rep.b=b;
  rep.ld50s=ld50s;

  fprintf('Plotting\n')
  subplot('Position',[0.632 0.700 0.164 0.250]);
  pmc=lgpdens([a' b'],xt,'range',[-2 3 -1 16],'gridn',40,'speedup','on');
  contour(XT1,XT2,reshape(pmc,50,50),'k');
  xlim([-2.4 4]),ylim([-4 24])
  xlabel('alpha')
  %ylabel('beta')
  ax=axis;
  h=line([ax(1), ax(2)], [0 0]);
  set(h, 'Color', 'k');
  h=line([0 0], [ax(3), ax(4)]);
  set(h, 'Color', 'k');
%   hzline
%   vzline
  title(sprintf('EP%s',grids))
  subplot('Position',[0.632 0.380 0.164 0.250]);
  hist(ld50s,-0.6:.04:0.6),set(gca,'xlim',[-.6 .6])
  h=get(gca,'Children');
  % set(h,'FaceColor',color1)
  set(gca,'ytick',[])
  ylim([0 2500])
  xlabel('LD50')
  h1=text(prctile(ld50s,2.5),2200,'2.5%','HorizontalAlignment','center');
  h2=text(prctile(ld50s,50),2350,'50%','HorizontalAlignment','center');
  h3=text(prctile(ld50s,97.5),2200,'97.5%','HorizontalAlignment','center');
  hl=line(repmat(prctile(ld50s,[2.5 50 97.5]),2,1),[0 0 0;2150 2300 2150],'Color','k');
  subplot('Position',[0.632 0.060 0.164 0.250]);
  qqplot(rmc.ld50s,ld50s)
  xlim([-.8 1.3])
  ylim([-50 60])
  ylabel('')
  box on
  drawnow

  fprintf('EP+fact%s approximation\n',grids)
  % Get samples from the joint distribution of the latent values at 0 and 1
  % to compute the corresponding linear model parameters alpha and beta
  % in Gelman et al (2004)
  fprintf('Sampling from the posterior of alpha and beta\n')
  fs = gp_rnd(gpia, x, y, [0 1]', 'z', N, 'zt', [5 5]', 'nsamp', 10000, 'fcorrections', 'fact');
  a=fs(1,:);b=fs(2,:)-fs(1,:);
  % compute samples from the LD50 given b>0 (see, Gelman et al (2004))
  ld50s=-a(b>0)./b(b>0);

  repc.fs=fs;
  repc.a=a;
  repc.b=b;
  repc.ld50s=ld50s;
  
  fprintf('Plotting\n')
  subplot('Position',[0.826 0.700 0.164 0.250]);
  pmc=lgpdens([a' b'],xt,'range',[-2 3 -1 16],'gridn',40,'speedup','on');
  contour(XT1,XT2,reshape(pmc,50,50),'k');
  xlim([-2.4 4]),ylim([-4 24])
  xlabel('alpha')
  %ylabel('beta')
  ax=axis;
  h=line([ax(1), ax(2)], [0 0]);
  set(h, 'Color', 'k');
  h=line([0 0], [ax(3), ax(4)]);
  set(h, 'Color', 'k');
%   hzline
%   vzline
  title(sprintf('EP+fact%s',grids))
  subplot('Position',[0.826 0.380 0.164 0.250]);
  hist(ld50s,-0.6:.04:0.6),set(gca,'xlim',[-.6 .6])
  h=get(gca,'Children');
  % set(h,'FaceColor',color1)
  set(gca,'ytick',[])
  ylim([0 2500])
  xlabel('LD50')
  h1=text(prctile(ld50s,2.5),2200,'2.5%','HorizontalAlignment','center');
  h2=text(prctile(ld50s,50),2350,'50%','HorizontalAlignment','center');
  h3=text(prctile(ld50s,97.5),2200,'97.5%','HorizontalAlignment','center');
  hl=line(repmat(prctile(ld50s,[2.5 50 97.5]),2,1),[0 0 0;2150 2300 2150],'Color','k');
  subplot('Position',[0.826 0.060 0.164 0.250]);
  qqplot(rmc.ld50s,ld50s)
  xlim([-.8 1.3])
  ylim([-50 60])
  ylabel('')
  box on
  drawnow

end