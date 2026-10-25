//-------------------------------------------------
// Light Amplification Visor
//-------------------------------------------------
class PortableLiteAmp:HDMagAmmo{
	default{
		//$Category "Gear/Hideous Destructor/Supplies"
		//$Title "Light Amp"
		//$Sprite "PVISB0"

		+inventory.invbar
		inventory.pickupmessage "$PICKUP_LITEAMP";
		inventory.icon "PVISA0";
		scale 0.5;
		hdmagammo.magbulk ENC_LITEAMP;
		tag "$TAG_LITEAMP";
		hdpickup.refid "lit";

		hdmagammo.maxperunit NITEVIS_MAGMAX;

		HDPickup.overlaypriority 20;
	}
	bool worn;
	PointLight nozerolight;
	override void DetachFromOwner(){
		worn=false;
		if(owner&&owner.player){
			UndoFullbright();
			SetShader("NiteVis",false);
			if(worn)owner.A_SetBlend("01 00 00",0.8,16);
		}
		super.DetachFromOwner();
	}
	override void PreTravelled(){
		if(hd_disableliteamponexit == true){
		worn=false;
		if(owner&&owner.player){
			UndoFullbright();
			SetShader("NiteVis",false);
			}
		}
	}
	double amplitude;
	double lastcvaramplitude;
	override bool isused(){return true;}
	override int getsbarnum(int flags){return int(amplitude);}
	override void AttachToOwner(actor other){
		super.AttachToOwner(other);
		if(owner&&owner.player){
			let cvv=cvar.getcvar("hd_nv",owner.player);
			double cvf=cvv.getfloat();
			amplitude=clamp(cvv.getfloat(),0,NITEVIS_MAX);
			if(
				cvf!=amplitude
				&&cvf!=999
			)cvv.setfloat(cvf);
		}
		else amplitude=frandom(0,NITEVIS_MAX);
		lastcvaramplitude=amplitude;
		syncamount();
	}
	int getintegrity(int index=0){return (mags[index]%NITEVIS_CYCLEUNIT);}
	int setintegrity(int newamt,int index=0,bool relative=false){
		if(amount!=mags.size())syncamount();
		int integrity=getintegrity(index);
		mags[index]-=integrity;

		if(relative)integrity+=newamt;
		else integrity=newamt;

		integrity=clamp(integrity,0,NITEVIS_MAXINTEGRITY);
		mags[index]+=integrity;
		return integrity;
	}
	void DoFullbright(){
		if(!owner||!owner.player)return;
		if(owner.player.fixedcolormap!=NITEVIS_INVULNCOLORMAP)owner.player.fixedcolormap=playerinfo.NUMCOLORMAPS+1;
		owner.player.fixedlightlevel=1;
		SetShader("NiteVis",false);
	}
	void UndoFullbright(){
		if(!owner||!owner.player)return;
		if(owner.player.fixedcolormap!=NITEVIS_INVULNCOLORMAP)owner.player.fixedcolormap=playerinfo.NOFIXEDCOLORMAP;
		owner.player.fixedlightlevel=-1;
	}
	override void Tick(){
		super.Tick();
		if(!owner||owner.health<1)worn=false;
		if(!worn)SetShader("NiteVis",false);
	}
	override void DoEffect(){
		super.DoEffect();
		if(!self||!owner||!owner.player)return;
		bool oldliteamp=(
			(sv_cheats||!multiplayer)
			&&cvar.getcvar("hd_nv",owner.player).getint()==999
		);

		//charge
		let bbb=HDBattery(owner.findinventory("HDBattery"));
		if(
			!!bbb
			&&bbb.mags.size()>0
		){
			//get the lowest non-empty
			int bbbindex=bbb.mags.size()-1;
			int bbblowest=20;
			for(int i=bbbindex;i>=0;i--){
				if(
					bbb.mags[i]>0
					&&bbb.mags[i]<bbblowest
				){
					bbbindex=i;
					bbblowest=bbb.mags[i];
				}
			}
			if(
				mags[0]<NITEVIS_MAGMAXCHARGE
				&&bbb.mags[bbbindex]>0
			){
				mags[0]+=NITEVIS_CYCLEUNIT;
				if(!random[rand1](0,(NITEVIS_BATCYCLE>>1)))bbb.mags[bbbindex]--;
			}
		}

		int chargedamount=mags[0];

//console.printf(chargedamount.."   "..NITEVIS_MAXINTEGRITY-(chargedamount%NITEVIS_CYCLEUNIT));
		let hpl=hdplayerpawn(owner);
		bool blurred=false;
		if (hpl.binvisible && hd_noblurwithliteamp == true) {blurred = true;}
		else if (hpl.bshadow) {
			switch(hpl.GetRenderStyle()) {
				case STYLE_Fuzzy:
				case STYLE_None:
					blurred=true;
				default: break;
			}
		}

		if(
			worn
			&&!blurred
		){

			//check if totally drained
			if(chargedamount<NITEVIS_CYCLEUNIT){
				owner.A_SetBlend("01 00 00",0.8,16);
				worn=false;
				return;
			}

			int spent=0;

			//update amplitude if player has set in the console
			double thiscvaramplitude=cvar.getcvar("hd_nv",owner.player).getfloat();
			if(thiscvaramplitude!=lastcvaramplitude){
				lastcvaramplitude=thiscvaramplitude;
				amplitude=thiscvaramplitude;
			}

			//actual goggle effect
			if(hd_liteampgogglefoveffect == true)owner.player.fov=max(30,min(owner.player.fov,90));
			double nv=min(chargedamount*(NITEVIS_MAX/20.),NITEVIS_MAX);
			if(!nv){
				if(thiscvaramplitude<0)amplitude=-0.00001;
				return;
			}
			if(oldliteamp){
				spent+=(NITEVIS_MAX/10);
				DoFullbright();
			}else{
				SetNVGStyle();
				UndoFullbright();
				nv=clamp(amplitude,-nv,nv);
				spent+=int(max(1,abs(nv*0.1)));
				SetShader("NiteVis",true);
				SetShaderU1f("NiteVis","exposure",nv);
				SetShaderU1f("NiteVis","timer",level.maptime);
				SetShaderU1i("NiteVis","u_resfactor",resfactor);
				SetShaderU1i("NiteVis","u_hscan",hscan);
				SetShaderU1i("NiteVis","u_vscan",vscan);
				SetShaderU1i("NiteVis","u_scanfactor",scanfactor);
				SetShaderU1f("NiteVis","u_scanstrength",scanstrength);
				SetShaderU1i("NiteVis","u_posterize",posterize);
				SetShaderU3f("NiteVis","u_posfilter",posfilter);
				SetShaderU1f("NiteVis","u_whiteclip",whiteclip);
				SetShaderU1f("NiteVis","u_desat",desat);
			}

			//flicker
			int integrity=(mags[0]%NITEVIS_CYCLEUNIT);
			if(integrity<NITEVIS_MAXINTEGRITY && hd_liteampflicker == true){
				int bkn=integrity+(chargedamount>>17)-abs(int(nv));
//				A_LogInt(bkn);
				if(!random[rand1](0,max(0,random[rand1](1,bkn)))){
					UndoFullbright();
					SetShader("NiteVis",false);
				}
			}

			//drain
			if(!(level.time&(1|2|4|8|16|32)))mags[0]-=NITEVIS_CYCLEUNIT*spent;

		}else{
			UndoFullbright();
			SetShader("NiteVis",false);
		}
	}
	enum NiteVis{
		NITEVIS_MAX=100,
		NITEVIS_MAXINTEGRITY=400,
		NITEVIS_CYCLEUNIT=NITEVIS_MAXINTEGRITY+1,
		NITEVIS_BATCYCLE=20000,
		NITEVIS_MAGMAXCHARGE=NITEVIS_CYCLEUNIT*NITEVIS_BATCYCLE,
		NITEVIS_MAGMAX=NITEVIS_MAGMAXCHARGE+NITEVIS_MAXINTEGRITY,
		NITEVIS_INVULNCOLORMAP=0,
	}
	override void DisplayOverlay(hdstatusbar sb,hdplayerpawn hpl){
		if(
			!worn
			||sb.blurred
		)return;
		sb.SetSize(0,320,200);
		sb.BeginHUD(forcescaled:true);
//		int gogheight=int(screen.getheight()*(1.6*90.)/max(30,min(sb.cplayer.fov,90)));
		int gogheight=int(screen.getheight()*(1.6*90.)/sb.cplayer.fov);
		int gogwidth=screen.getwidth()*gogheight/screen.getheight();
		int gogoffsx=-((gogwidth-screen.getwidth())>>1);
		int gogoffsy=-((gogheight-screen.getheight())>>1);

		screen.drawtexture(
			texman.checkfortexture("gogmask",texman.type_any),
			true,
			gogoffsx-(int(hpl.wepbob.x)),
			gogoffsy-(int(hpl.wepbob.y)),
			DTA_DestWidth,gogwidth,DTA_DestHeight,gogheight,
			true
		);
	}
	states{
	spawn:
		PVIS A -1;
	use:
		TNT1 A 0{
			int cmd=player.cmd.buttons;
			if(cmd&BT_USE){
				A_StartSound("lightamp/adjust",CHAN_AUTO);
				double am=cmd&BT_ZOOM?-5:5;
				invoker.amplitude=clamp(am+abs(invoker.amplitude),0,NITEVIS_MAX);
			}else if(cmd&BT_USER3){
				invoker.firsttolast();
				int amt=invoker.mags[0];
				A_Log(Stringtable.Localize("$LITEAMP_GOGGLESAT")..amt*100/NITEVIS_MAGMAXCHARGE..Stringtable.Localize("$LITEAMP_CHARGE")..((amt%NITEVIS_CYCLEUNIT)>>2)..Stringtable.Localize("$LITEAMP_INTEGRITY"),true);
			}else{
				A_SetBlend("01 00 00",0.8,16);
				if(HDMagAmmo.NothingLoaded(self,"PortableLiteAmp")){
					A_Log(Stringtable.Localize("$LITEAMP_NOPOWER"),true);
					A_StartSound("lightamp/deactivate",CHAN_AUTO);
					invoker.worn=false;
					return;
				}
				if(invoker.worn)
				{
					A_StartSound("lightamp/deactivate",CHAN_AUTO);
					invoker.worn=false;
				}else{
					A_StartSound("lightamp/activate",CHAN_AUTO);
					invoker.worn=true;
					if(!invoker.nozerolight)invoker.nozerolight=PointLight(spawn("visorlight",pos,ALLOW_REPLACE));
					invoker.nozerolight.target=self;
				}
			}
		}fail;
	}
}
class VisorLight:PointLight{
	override void postbeginplay(){
		super.postbeginplay();
		args[0]=1;
		args[1]=0;
		args[2]=0;
		args[3]=256;
		args[4]=0;
	}
	override void tick(){
		if(!target){
			destroy();
			return;
		}
		if(
			target.findinventory("PortableLiteAmp")
			&&portableliteamp(target.findinventory("PortableLiteAmp")).worn
		)args[3]=256;else args[3]=0;
		setorigin((target.pos.xy,target.pos.z+target.height),true);
	}
}
extend class PortableLiteAmp {
	transient CVar NVGStyle;
	int style;
	int resfactor,scanfactor,hscan,vscan,posterize;
	double scanstrength,whiteclip,desat;
	vector3 posfilter,negfilter;

	void SetNVGStyle() {
		if (!NVGStyle) NVGStyle = CVar.GetCVar("hd_nv_style",owner.player);
		int style = NVGStyle.GetInt();
		switch (style) {
			case 0: // Hideous green
				resfactor=1;hscan=1;vscan=0;scanfactor=8;scanstrength=0.1;posterize=24;posfilter=(0,1,0);whiteclip=0.25;desat=0.0;break;
			case 1: // Hideous red
				resfactor=1;hscan=1;vscan=0;scanfactor=8;scanstrength=0.1;posterize=24;posfilter=(1,0,0);whiteclip=0.25;desat=0.0;break;
			case 2: // Analog green
				resfactor=4;hscan=1;vscan=0;scanfactor=resfactor;scanstrength=0.1;posterize=256;posfilter=(0.25,1.0,0.25);whiteclip=0.6;desat=0.1;break;
			case 3: // Analog amber
				resfactor=4;hscan=1;vscan=0;scanfactor=resfactor;scanstrength=0.1;posterize=256;posfilter=(1.0,1.0,0.25);whiteclip=0.6;desat=0.1;break;
			case 4: // Digital green
				resfactor=3;hscan=1;vscan=1;scanfactor=resfactor;scanstrength=0.025;posterize=16;posfilter=(0.05,1.0,0.05);whiteclip=0.9;desat=0.0;break;
			case 5: // Digital amber
				resfactor=3;hscan=1;vscan=1;scanfactor=resfactor;scanstrength=0.025;posterize=16;posfilter=(1.0,1.0,0.05);whiteclip=0.9;desat=0.0;break;
			case 6: // Modern green
				resfactor=2;hscan=1;vscan=0;scanfactor=2;scanstrength=0.1;posterize=256;posfilter=(0.1,1.0,0.1);whiteclip=0.8;desat=0.0;break;
			default:
			case 8: // Truecolor
				resfactor=1;hscan=1;vscan=0;scanfactor=2;scanstrength=0.1;posterize=256;posfilter=(0.5,1.0,0.5);whiteclip=1.0;desat=0.5;break;
			case 9: // Old Modern Green
				resfactor=2;hscan=1;vscan=0;scanfactor=2;scanstrength=0.1;posterize=256;posfilter=(0.0,1.0,0.75);whiteclip=0.8;desat=0.0;break;
		}
	}
}
